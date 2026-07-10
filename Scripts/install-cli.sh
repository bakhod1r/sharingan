#!/usr/bin/env bash
#
# install-cli.sh — build the `tired` CLI and symlink it onto your PATH.
#
#   Scripts/install-cli.sh              # → /usr/local/bin/tired (release build)
#   PREFIX=~/.local/bin Scripts/install-cli.sh
#   Scripts/install-cli.sh --debug
#
# Uninstall:  rm "$(command -v tired)"
#
set -euo pipefail

CONFIG="release"
[[ "${1:-}" == "--debug" ]] && CONFIG="debug"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

PREFIX="${PREFIX:-/usr/local/bin}"
BINDIR="$(swift build -c "$CONFIG" --show-bin-path)"
SRC="$BINDIR/tired"

echo "▸ Building tired ($CONFIG)…"
swift build -c "$CONFIG" --product tired

DEST="$PREFIX/tired"

# Copy (not symlink): a symlink into .build dangles as soon as `make clean`
# runs, silently breaking `tired` until the next release build.
if mkdir -p "$PREFIX" 2>/dev/null && cp "$SRC" "$DEST" 2>/dev/null; then
  echo "✅ Installed → $DEST"
else
  # Fall back to sudo if $PREFIX isn't writable (e.g. a fresh /usr/local/bin).
  echo "  ! $PREFIX not writable; trying sudo…"
  sudo mkdir -p "$PREFIX"
  sudo cp "$SRC" "$DEST"
  echo "✅ Installed → $DEST"
fi

case ":$PATH:" in
  *":$PREFIX:"*) : ;;
  *) echo "  ⚠︎ $PREFIX is not on your PATH. Add:  export PATH=\"$PREFIX:\$PATH\"" ;;
esac

echo "Try:  tired help"
