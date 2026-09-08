#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
PILOT_SUITE=unit
if [[ $# -gt 0 ]]; then
  [[ $# -eq 2 && "$1" == --suite ]] || { echo "Usage: $0 [--suite unit|contracts|desktop]" >&2; exit 2; }
  PILOT_SUITE="$2"
fi
case "$PILOT_SUITE" in
  unit) pilot_swift test ;;
  contracts) python3 "$PILOT_ROOT/script/test_harness.py" ;;
  desktop) python3 "$PILOT_ROOT/script/desktop_tests.py" --check controlled-windows ;;
  *) echo "Unknown test suite: $PILOT_SUITE" >&2; exit 2 ;;
esac
