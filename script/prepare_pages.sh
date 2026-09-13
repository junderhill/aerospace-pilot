#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

[[ $# -eq 0 ]] || { echo "Usage: $0" >&2; exit 2; }

pages_directory="$PILOT_ROOT/dist/pages"
rm -rf "$pages_directory"
mkdir -p "$pages_directory/assets"
cp -R "$PILOT_ROOT/website/." "$pages_directory/"
cp "$PILOT_ROOT/Resources/Icons/Assets.xcassets/AppIcon.appiconset/icon_512x512.png" \
  "$pages_directory/assets/app-icon.png"

python3 "$PILOT_ROOT/script/validate_pages.py" "$pages_directory"
echo "Prepared GitHub Pages site: $pages_directory"
