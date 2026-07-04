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

mkdir -p "$PREFIX"
DEST="$PREFIX/tired"

# Prefer a symlink to the build product so re-builds are picked up automatically.
if ln -sf "$SRC" "$DEST" 2>/dev/null; then
  echo "✅ Linked $DEST → $SRC"
else
  # Fall back to a copy if $PREFIX needs privileges the symlink couldn't get.
  echo "  ! symlink failed; trying sudo copy…"
  sudo cp "$SRC" "$DEST"
  echo "✅ Copied → $DEST"
fi

case ":$PATH:" in
  *":$PREFIX:"*) : ;;
  *) echo "  ⚠︎ $PREFIX is not on your PATH. Add:  export PATH=\"$PREFIX:\$PATH\"" ;;
esac

echo "Try:  tired help"
