#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

[[ $# -eq 1 ]] || { echo "Usage: $0 VERSION" >&2; exit 2; }
PILOT_VERSION="${1#v}"
[[ "$PILOT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] || {
  echo "Version must look like 1.2.3 or 1.2.3-beta.1" >&2
  exit 2
}

PILOT_BUILD_NUMBER="${PILOT_BUILD_NUMBER:-1}"
PILOT_RELEASE_ARCHS="${PILOT_RELEASE_ARCHS:-arm64,x86_64}"
swift_arguments=(build -c release)
IFS=',' read -r -a architectures <<< "$PILOT_RELEASE_ARCHS"
for architecture in "${architectures[@]}"; do
  swift_arguments+=(--arch "$architecture")
done

pilot_swift "${swift_arguments[@]}"
PILOT_BIN="$(pilot_swift "${swift_arguments[@]}" --show-bin-path)"
export PILOT_VERSION PILOT_BUILD_NUMBER
python3 "$PILOT_ROOT/script/stage_bundle.py" "$PILOT_ROOT" "$PILOT_BIN"

release_directory="$PILOT_ROOT/dist/release"
archive="$release_directory/AeroSpace-Pilot-$PILOT_VERSION.zip"
mkdir -p "$release_directory"
rm -f "$archive"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$PILOT_ROOT/dist/AeroSpace Pilot.app" "$archive"
(
  cd "$release_directory"
  /usr/bin/shasum -a 256 "$(basename "$archive")" > SHA256SUMS.txt
)

echo "Release archive: $archive"
echo "Checksum file: $release_directory/SHA256SUMS.txt"
