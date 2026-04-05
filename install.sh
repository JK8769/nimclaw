#!/usr/bin/env bash
# NimClaw installer — download pre-built binary for your platform.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/owaf/nimclaw/main/install.sh | sh
#   curl -fsSL https://raw.githubusercontent.com/owaf/nimclaw/main/install.sh | sh -s -- --dir /opt/nimclaw
#
# Environment variables:
#   NIMCLAW_INSTALL_DIR  Override binary install directory (default: ~/.local/bin)
#   NIMCLAW_LIB_DIR      Override library/assets directory (default: ~/.local/lib/nimclaw)
#   NIMCLAW_VERSION      Install a specific version (default: latest)

set -euo pipefail

REPO="JK8769/nimclaw"
INSTALL_DIR="${NIMCLAW_INSTALL_DIR:-$HOME/.local/bin}"
LIB_DIR="${NIMCLAW_LIB_DIR:-$HOME/.local/lib/nimclaw}"
VERSION="${NIMCLAW_VERSION:-latest}"

# ── Parse flags ──────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --dir)    INSTALL_DIR="$2"; shift 2 ;;
    --lib)    LIB_DIR="$2"; shift 2 ;;
    --version) VERSION="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# ── Detect platform ─────────────────────────────────────────────
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$OS" in
  linux)  OS="linux" ;;
  darwin) OS="darwin" ;;
  *) echo "Unsupported OS: $OS"; exit 1 ;;
esac

case "$ARCH" in
  x86_64|amd64)   ARCH="amd64" ;;
  aarch64|arm64)   ARCH="arm64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

ARTIFACT="nimclaw-${OS}-${ARCH}"
echo "Platform: ${OS}/${ARCH}"

# ── Resolve version ─────────────────────────────────────────────
if [ "$VERSION" = "latest" ]; then
  VERSION="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | grep '"tag_name"' | head -1 | cut -d'"' -f4)"
  if [ -z "$VERSION" ]; then
    echo "Error: could not determine latest version. Set NIMCLAW_VERSION manually."
    exit 1
  fi
fi
echo "Version:  ${VERSION}"

# ── Download ─────────────────────────────────────────────────────
URL="https://github.com/${REPO}/releases/download/${VERSION}/${ARTIFACT}.tar.gz"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

echo "Downloading ${URL}..."
curl -fSL "$URL" -o "$TMPDIR/${ARTIFACT}.tar.gz"
tar xzf "$TMPDIR/${ARTIFACT}.tar.gz" -C "$TMPDIR"

# ── Install ──────────────────────────────────────────────────────
mkdir -p "$INSTALL_DIR"
mkdir -p "$LIB_DIR/channels/bin"

echo "Installing to ${INSTALL_DIR}..."
cp "$TMPDIR/${ARTIFACT}/nimclaw" "$INSTALL_DIR/nimclaw"
chmod +x "$INSTALL_DIR/nimclaw"

# Channel CLIs
if [ -d "$TMPDIR/${ARTIFACT}/channels-bin" ]; then
  for cli in "$TMPDIR/${ARTIFACT}/channels-bin"/*; do
    [ -f "$cli" ] || continue
    cp "$cli" "$LIB_DIR/channels/bin/"
    chmod +x "$LIB_DIR/channels/bin/$(basename "$cli")"
  done
  echo "Channel CLIs installed to ${LIB_DIR}/channels/bin/"
fi

# Runtime assets (templates, skills, plugins)
for dir in templates skills plugins; do
  if [ -d "$TMPDIR/${ARTIFACT}/${dir}" ]; then
    mkdir -p "$LIB_DIR/${dir}"
    cp -r "$TMPDIR/${ARTIFACT}/${dir}/." "$LIB_DIR/${dir}/"
  fi
done

# ── PATH check ───────────────────────────────────────────────────
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$INSTALL_DIR"; then
  echo ""
  echo "Add to your shell profile:"
  echo "  export PATH=\"${INSTALL_DIR}:\$PATH\""
  echo ""
fi

if ! echo "$PATH" | tr ':' '\n' | grep -qx "$LIB_DIR/channels/bin"; then
  echo "For channel CLIs, also add:"
  echo "  export PATH=\"${LIB_DIR}/channels/bin:\$PATH\""
  echo ""
fi

# ── Done ─────────────────────────────────────────────────────────
echo "Installed nimclaw ${VERSION} to ${INSTALL_DIR}"
echo "Runtime assets in ${LIB_DIR}"
echo ""
echo "Next steps:"
echo "  nimclaw service new         # create a service"
echo "  nimclaw service onboard     # guided setup"
echo "  nimclaw service run         # start the gateway"
