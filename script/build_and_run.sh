#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
PILOT_MODE="${1:-run}"
[[ $# -le 1 ]] || { echo "Usage: $0 [--verify|--debug|--logs|--telemetry]" >&2; exit 2; }
case "$PILOT_MODE" in run|--verify|--debug|--logs|--telemetry) ;; *) echo "Unknown run mode: $PILOT_MODE" >&2; exit 2;; esac
python3 "$PILOT_ROOT/script/launch.py" stop "$PILOT_ROOT"
"$PILOT_ROOT/script/build.sh"
if [[ "$PILOT_MODE" == --debug ]]; then
  exec lldb -- "$PILOT_ROOT/dist/AeroSpace Pilot.app/Contents/MacOS/AeroSpacePilot"
fi
python3 "$PILOT_ROOT/script/launch.py" launch "$PILOT_ROOT"
case "$PILOT_MODE" in
  --logs) exec /usr/bin/log stream --info --style compact --predicate 'process == "AeroSpacePilot"' ;;
  --telemetry) exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "uk.jason.aerospace-pilot"' ;;
esac
