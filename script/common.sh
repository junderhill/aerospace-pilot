#!/usr/bin/env bash
set -euo pipefail
PILOT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PILOT_SWIFT="${PILOT_SWIFT:-$(command -v swift || true)}"
export CLANG_MODULE_CACHE_PATH="$PILOT_ROOT/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PILOT_ROOT/.build/swift-cache"
pilot_swift() {
  "$PILOT_SWIFT" "$@" --package-path "$PILOT_ROOT" --scratch-path "$PILOT_ROOT/.build" \
    --cache-path "$PILOT_ROOT/.build/cache" --config-path "$PILOT_ROOT/.build/config" --security-path "$PILOT_ROOT/.build/security"
}
