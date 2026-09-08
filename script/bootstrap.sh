#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"
[[ $# -eq 0 ]] || { echo "Usage: $0" >&2; exit 2; }
"$PILOT_ROOT/script/doctor.sh"
pilot_swift package resolve
echo "Bootstrap ready. No external package dependencies."
