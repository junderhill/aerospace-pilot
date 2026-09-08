#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--desktop" ) ]]; then
  echo "Usage: $0 [--desktop]" >&2; exit 2
fi
[[ "$(uname -s)" == Darwin ]] || { echo "macOS 14 or newer is required." >&2; exit 1; }
[[ -n "$PILOT_SWIFT" && -x "$PILOT_SWIFT" ]] || { echo "Install Xcode with Swift 6 or newer." >&2; exit 1; }
xcode-select -p
"$PILOT_SWIFT" --version
python3 --version
python3 - <<'PY'
import re, subprocess, sys
mac = subprocess.check_output(['sw_vers','-productVersion'], text=True).strip()
print('macOS', mac)
if int(mac.split('.')[0]) < 14: sys.exit('macOS 14 or newer is required.')
version = subprocess.check_output(['xcrun','swift','--version'], text=True)
match = re.search(r'Swift version (\d+)', version)
if not match or int(match[1]) < 6: sys.exit('Swift 6 or newer is required.')
PY
if [[ "${1:-}" == --desktop ]]; then
  "$PILOT_ROOT/script/build.sh"
  "$PILOT_ROOT/dist/pilot" doctor
fi
