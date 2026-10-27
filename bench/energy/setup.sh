#!/usr/bin/env bash
# Window fixture: opens 2 Terminal windows on each of workspaces 1..3 using the running
# WM's CLI, then returns to workspace 1. `./setup.sh teardown` closes only those windows.
#
#   ./setup.sh aerospace|rift      # create fixture
#   ./setup.sh teardown            # close fixture windows
set -euo pipefail
cd "$(dirname "$0")"
ids=.fixture_window_ids

if [ "${1:-}" = teardown ]; then
  [ -f $ids ] || exit 0
  while read -r id; do
    osascript -e "tell application \"Terminal\" to close (every window whose id is $id)" 2>/dev/null || true
  done < $ids
  rm -f $ids
  exit 0
fi

wm=${1:?aerospace|rift}
to_ws() { # 1-based workspace number
  case $wm in
    aerospace) aerospace workspace "$1" ;;
    rift) rift-cli execute workspace switch $(( $1 - 1 )) ;;
  esac
}

: > $ids
for ws in 1 2 3; do
  to_ws $ws; sleep 0.5
  for _ in 1 2; do
    osascript -e 'tell application "Terminal"
      do script "clear"
      return id of front window
    end tell' >> $ids
    sleep 1
  done
done
to_ws 1
echo "fixture ready: $(wc -l < $ids | tr -d ' ') windows"
