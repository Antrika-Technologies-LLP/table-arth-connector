#!/usr/bin/env sh
# TableArth Connector Agent installer for Linux and macOS.
#
#   curl -fsSL https://raw.githubusercontent.com/Antrika-Technologies-LLP/table-arth-connector/main/bin/install.sh | sh
#
# Override the download source with RELEASE_BASE, or the install dir with PREFIX.
set -e

RELEASE_BASE="${RELEASE_BASE:-https://raw.githubusercontent.com/Antrika-Technologies-LLP/table-arth-connector/main/bin}"
PREFIX="${PREFIX:-/usr/local/bin}"
BIN="tac-agent"

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"
case "$arch" in
  x86_64|amd64)  arch=amd64 ;;
  arm64|aarch64) arch=arm64 ;;
  *) echo "unsupported architecture: $arch" >&2; exit 1 ;;
esac
case "$os" in
  linux|darwin) ;;
  *) echo "unsupported OS: $os — see docs/INSTALL.md for Windows" >&2; exit 1 ;;
esac

url="${RELEASE_BASE}/${BIN}-${os}-${arch}"
tmp="$(mktemp)"
echo "Downloading ${url} ..."
curl -fsSL "$url" -o "$tmp"
chmod +x "$tmp"

echo "Installing to ${PREFIX}/${BIN} ..."
if [ -w "$PREFIX" ]; then
  mv "$tmp" "${PREFIX}/${BIN}"
else
  sudo mv "$tmp" "${PREFIX}/${BIN}"
fi

echo "Installed: $("${PREFIX}/${BIN}" -version)"
echo
echo "Next steps:"
echo "  1. Create your config (see docs/INSTALL.md or examples/agent.config.example.yaml)"
echo "  2. Run: ${BIN} -config /path/to/config.yaml"
