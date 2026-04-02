#!/usr/bin/env bash
# Build lark-cli from the thridparty/cli submodule.
# Requires Go 1.23+ and Python 3 (for metadata fetching).
#
# Usage:
#   ./tools/build_lark_cli.sh              # build for current platform
#   ./tools/build_lark_cli.sh linux amd64  # cross-compile
#
# The binary is placed in thridparty/cli/lark-cli (or .exe on Windows).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI_DIR="$ROOT_DIR/thridparty/cli"

if [ ! -f "$CLI_DIR/main.go" ]; then
  echo "Submodule not initialized. Run: git submodule update --init thridparty/cli" >&2
  exit 1
fi

TARGET_OS="${1:-$(go env GOOS)}"
TARGET_ARCH="${2:-$(go env GOARCH)}"

echo "Building lark-cli for ${TARGET_OS}/${TARGET_ARCH}..."

cd "$CLI_DIR"

OUTPUT="lark-cli"
if [ "$TARGET_OS" = "windows" ]; then
  OUTPUT="lark-cli.exe"
fi

# Fetch API metadata (required by build)
python3 scripts/fetch_meta.py

GOOS="$TARGET_OS" GOARCH="$TARGET_ARCH" \
  go build -trimpath -ldflags "-s -w" -o "$OUTPUT" .

echo "Built: $CLI_DIR/$OUTPUT"
