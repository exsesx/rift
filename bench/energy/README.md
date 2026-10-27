# WM energy benchmark (rift vs AeroSpace)

Measures what a window manager costs in CPU, wakeups and power on macOS.
Runs on the Mac; nothing here was executed on macOS by the author, so expect to fix
small things on first run (see "First-run checks").

## Files

| File | Purpose |
| --- | --- |
| `driver.swift` | Posts synthetic input: `keys` (WM hotkeys), `mouse` (cursor sweeps), `type` (F13 presses) |
| `measure.sh` | One run: settle, powermetrics + battery sampling + per-process CPU time while the driver runs |
| `setup.sh` | Opens 2 Terminal windows on each of workspaces 1..3 via the WM's CLI; `teardown` closes them |
| `analyze.py` | Per-run metrics and median/min/max per (phase, wm) |
| `configs/` | Bindings both WMs need so the `keys` phase does the same work |

## Protocol

1. Prepare: plug in or unplug consistently (battery numbers need battery power), fixed brightness,
   Low Power Mode off, Wi-Fi and Bluetooth state fixed, quit everything except Terminal,
   disable Spotlight indexing for the session if possible (`sudo mdutil -a -i off`, revert after).
   A fresh macOS user account with no login items is the cleanest option.
2. Grant Accessibility to Terminal (System Settings > Privacy & Security > Accessibility) so
   `driver.swift` can post events. Needs Xcode Command Line Tools for `swiftc`.
3. Merge `configs/*-bench.toml` into each WM's config. Both WMs: animations off, focus-follows-mouse
   off, menu bar/overview off for the baseline.
4. For each WM, alternating (A B A B ...), at least 5 rounds:
   ```sh
   # start exactly one WM, then:
   ./setup.sh rift               # or aerospace
   ./measure.sh rift idle 300
   ./measure.sh rift keys 300 2  # 2 actions/s
   ./measure.sh rift type 300 8  # 8 key presses/s, no bindings hit
   ./setup.sh teardown
   ```
5. Variants, one change at a time: rift `animate = true`; focus-follows-mouse on in both and
   `./measure.sh <wm> mouse 300 60`; rift menu bar / mission control on.
6. `python3 analyze.py results/ --csv results.csv`

Switch WMs with `rift-cli service stop` / `open -a AeroSpace` and the reverse
(`osascript -e 'quit app "AeroSpace"'`, `rift-cli service start`).

## What to read

- `wm_cpu_ms_s(ps)`: WM CPU time per wall second from `ps` deltas. The most sensitive and least
  noisy number; 1.0 = 0.1% of one core.
- `wm_idle_wakeups_s`: package wakeups caused by the WM. Matters most for idle battery life.
- `wm_energy_impact_s`: Apple's unitless model (same as Activity Monitor). Comparable between
  processes on the same Mac, not a wattage.
- `windowserver_*`: a WM pushes work into WindowServer (moves, animations, overlays). Compare it too.
- `package_mW`, `battery_W`: whole-system. Usually too noisy to resolve a WM's share; use them as
  a sanity check, not the verdict.

Treat a difference as real only if the min-max ranges of the two WMs do not overlap across
5+ alternating rounds.

## First-run checks

- `powermetrics` plist keys vary by macOS version. If `wm_cpu_ms_s` prints nothing, run
  `sudo powermetrics -f plist --samplers tasks --show-process-energy -n 1 | plutil -p -` and adjust
  the key names in `analyze.py` (`task_fields`, `combined_power`).
- Process names assumed: `rift` and `AeroSpace` (`pgrep -x`). Check with `pgrep -lf rift`.
- Battery current key may be `Amperage` or `InstantAmperage`; both are recorded.
