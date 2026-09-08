#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[[ $# -eq 0 ]] || { echo "Usage: $0" >&2; exit 2; }
pilot_swift build
PILOT_BIN="$(pilot_swift build --show-bin-path)"
python3 "$PILOT_ROOT/script/stage_bundle.py" "$PILOT_ROOT" "$PILOT_BIN"
echo "Built: $PILOT_ROOT/dist/AeroSpace Pilot.app"
