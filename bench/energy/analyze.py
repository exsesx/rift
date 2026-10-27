#!/usr/bin/env python3
"""Summarize measure.sh runs: python3 analyze.py results/ [--csv out.csv]

Per run: WM and WindowServer CPU (ms/s), WM energy impact and wakeups (powermetrics),
package power (mW), and battery discharge (W, only when on battery).
Then median and min-max per (wm, phase) across runs.
"""
import csv
import json
import plistlib
import statistics
import sys
from collections import defaultdict
from pathlib import Path


def parse_ps_time(s):
    # macOS ps "time": [[dd-]hh:]mm:ss.ss
    days = 0
    if "-" in s:
        d, s = s.split("-", 1)
        days = int(d)
    secs = 0.0
    for part in s.split(":"):
        secs = secs * 60 + float(part)
    return days * 86400 + secs


def signed64(v):
    v = int(v)
    return v - (1 << 64) if v >= (1 << 63) else v


def load_powermetrics(path):
    raw = path.read_bytes()
    samples = []
    for chunk in raw.split(b"\0"):
        chunk = chunk.strip()
        if chunk:
            try:
                samples.append(plistlib.loads(chunk))
            except Exception:
                pass
    return samples


def mean(xs):
    xs = [x for x in xs if x is not None]
    return sum(xs) / len(xs) if xs else None


def summarize_run(run):
    meta = json.loads((run / "meta.json").read_text())
    proc = meta["proc"]
    row = {"run": run.name, "wm": meta["wm"], "phase": meta["phase"], "on_battery": meta["on_battery"]}

    start = (run / "cputime_start").read_text().split()
    end = (run / "cputime_end").read_text().split()
    secs = float(meta["seconds"])
    row["wm_cpu_ms_s(ps)"] = (parse_ps_time(end[0]) - parse_ps_time(start[0])) * 1000 / secs
    row["windowserver_cpu_ms_s(ps)"] = (parse_ps_time(end[1]) - parse_ps_time(start[1])) * 1000 / secs

    samples = load_powermetrics(run / "powermetrics.plist")
    row["samples"] = len(samples)
    task_fields = {
        "wm_cpu_ms_s": "cputime_ms_per_s",
        "wm_energy_impact_s": "energy_impact_per_s",
        "wm_idle_wakeups_s": "idle_wakeups_per_s",
        "wm_intr_wakeups_s": "intr_wakeups_per_s",
    }
    per = defaultdict(list)
    for s in samples:
        for t in s.get("tasks", []):
            if t.get("name") == proc:
                for col, key in task_fields.items():
                    per[col].append(t.get(key))
            elif t.get("name") == "WindowServer":
                per["windowserver_energy_impact_s"].append(t.get("energy_impact_per_s"))
        p = s.get("processor", {})
        per["package_mW"].append(p.get("combined_power", p.get("package_watts", None)))
        per["cpu_mW"].append(p.get("cpu_power"))
        per["gpu_mW"].append(s.get("gpu", {}).get("gpu_power", p.get("gpu_power")))
    for col, xs in per.items():
        row[col] = mean(xs)

    batt = run / "battery.txt"
    if meta["on_battery"] and batt.exists():
        watts = []
        for line in batt.read_text().splitlines():
            parts = line.split()
            if len(parts) >= 3:
                volt_mv = int(parts[1])
                amp_ma = signed64(parts[3] if len(parts) > 3 else parts[2])
                watts.append(-volt_mv * amp_ma / 1e6)
        row["battery_W"] = mean(watts)
    return row


def main():
    root = Path(sys.argv[1] if len(sys.argv) > 1 else "results")
    rows = [summarize_run(r) for r in sorted(root.iterdir()) if (r / "meta.json").exists()]
    if not rows:
        sys.exit(f"no runs in {root}")
    if "--csv" in sys.argv:
        out = sys.argv[sys.argv.index("--csv") + 1]
        cols = sorted({k for r in rows for k in r}, key=lambda k: (k not in ("run", "wm", "phase"), k))
        with open(out, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=cols)
            w.writeheader()
            w.writerows(rows)

    metrics = ["wm_cpu_ms_s(ps)", "wm_cpu_ms_s", "wm_energy_impact_s", "wm_idle_wakeups_s",
               "windowserver_cpu_ms_s(ps)", "windowserver_energy_impact_s", "package_mW", "battery_W"]
    groups = defaultdict(list)
    for r in rows:
        groups[(r["phase"], r["wm"])].append(r)
    for (phase, wm), rs in sorted(groups.items()):
        print(f"\n== {phase} / {wm}  (n={len(rs)})")
        for m in metrics:
            xs = [r[m] for r in rs if r.get(m) is not None]
            if xs:
                print(f"  {m:30s} median {statistics.median(xs):10.2f}   min {min(xs):10.2f}   max {max(xs):10.2f}")
    if any(r.get("samples", 0) and r.get("wm_cpu_ms_s") is None for r in rows):
        print("\nnote: WM missing from some powermetrics task lists; check the process name in meta.json")


if __name__ == "__main__":
    main()
