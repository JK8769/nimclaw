#!/usr/bin/env bash
# Build the NKN bridge binary for the current or target platform.
# Requires Go 1.21+ and CGO enabled.
#
# Usage:
#   ./tools/build_libnkn.sh              # build for current OS/arch
#   ./tools/build_libnkn.sh linux amd64  # cross-compile for linux/amd64
#
# Output goes to src/nimclaw/libnkn/nkn_bridge

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
NKN_DIR="$ROOT_DIR/src/nimclaw/libnkn"

TARGET_OS="${1:-$(go env GOOS)}"
TARGET_ARCH="${2:-$(go env GOARCH)}"

echo "Building nkn_bridge for ${TARGET_OS}/${TARGET_ARCH}..."

cd "$NKN_DIR"

OUTPUT="nkn_bridge"
if [ "$TARGET_OS" = "windows" ]; then
  OUTPUT="nkn_bridge.exe"
fi

CGO_ENABLED=0 GOOS="$TARGET_OS" GOARCH="$TARGET_ARCH" \
  go build -o "$OUTPUT" nkn_bridge.go

echo "Built: $NKN_DIR/$OUTPUT"
