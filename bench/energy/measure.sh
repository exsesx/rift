#!/usr/bin/env bash
# One measurement run against the WM that is currently running.
#
#   ./measure.sh <wm> <phase> <seconds> [rate]
#     wm:    aerospace | rift
#     phase: idle | keys | mouse | type
#
# Writes results/<timestamp>-<wm>-<phase>/ with powermetrics plist, battery samples and
# per-process CPU time. Analyze with: python3 analyze.py results/
set -euo pipefail
cd "$(dirname "$0")"

wm=${1:?wm}; phase=${2:?phase}; secs=${3:?seconds}; rate=${4:-}
settle=${SETTLE:-60}

case $wm in
  aerospace) proc=AeroSpace; other=rift ;;
  rift)      proc=rift;      other=AeroSpace ;;
  *) echo "unknown wm $wm" >&2; exit 2 ;;
esac

pgrep -x "$proc" >/dev/null || { echo "$proc is not running" >&2; exit 1; }
if pgrep -x "$other" >/dev/null; then echo "$other is also running; stop it first" >&2; exit 1; fi

out="results/$(date +%Y%m%d-%H%M%S)-$wm-$phase"
mkdir -p "$out"
sudo -v

on_battery=$(pmset -g batt | head -1 | grep -q "Battery Power" && echo true || echo false)
cat > "$out/meta.json" <<JSON
{"wm":"$wm","proc":"$proc","phase":"$phase","seconds":$secs,"rate":"$rate",
 "on_battery":$on_battery,"macos":"$(sw_vers -productVersion)","model":"$(sysctl -n hw.model)",
 "low_power_mode":"$(pmset -g | awk '/lowpowermode/{print $2}')",
 "wm_version":"$( [ $wm = rift ] && (rift-cli --version 2>/dev/null || true) || (aerospace --version 2>/dev/null | head -1 || true))"}
JSON

# Precompile the driver so swiftc does not run inside the window.
if [ "$phase" != idle ] && { [ ! -x .driver ] || [ driver.swift -nt .driver ]; }; then
  swiftc -O driver.swift -o .driver
fi

echo "settling ${settle}s (hands off keyboard and mouse)"; sleep "$settle"

cputime() { ps -o time= -p "$(pgrep -x "$1" | head -1)" | tr -d ' '; }
echo "$(cputime "$proc") $(cputime WindowServer)" > "$out/cputime_start"

sudo powermetrics -f plist --samplers tasks,cpu_power,gpu_power --show-process-energy \
  -i 1000 -n "$secs" -o "$out/powermetrics.plist" >/dev/null 2>&1 &
pm=$!

( while kill -0 $pm 2>/dev/null; do
    printf '%s ' "$(date +%s)"; ioreg -rn AppleSmartBattery | awk -F' = ' '
      /"Voltage" =/{v=$2} /"Amperage" =/{a=$2} /"InstantAmperage" =/{i=$2}
      END{print v, a, i}'
    sleep 5
  done ) > "$out/battery.txt" &

if [ "$phase" = idle ]; then
  sleep "$secs"
else
  ./.driver "$phase" "$secs" ${rate:+"$rate"} > "$out/driver.txt"
fi
wait $pm || true
echo "$(cputime "$proc") $(cputime WindowServer)" > "$out/cputime_end"
echo "done: $out"
