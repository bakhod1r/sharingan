#!/usr/bin/env bash
#
# notarize.sh <file.dmg|.zip|.app> — submit to Apple's notary service, wait,
# staple the ticket, validate. Credentials via App Store Connect API key:
#   ASC_KEY_ID     — Key ID (App Store Connect → Integrations)
#   ASC_ISSUER_ID  — Issuer ID
#   ASC_KEY_P8     — contents of the downloaded .p8 (not a path)
#
set -euo pipefail

TARGET="${1:?usage: notarize.sh <file>}"
: "${ASC_KEY_ID:?ASC_KEY_ID is not set}"
: "${ASC_ISSUER_ID:?ASC_ISSUER_ID is not set}"
: "${ASC_KEY_P8:?ASC_KEY_P8 is not set}"

# notarytool wants the key as a file; keep it out of the repo and shred after.
KEYFILE="$(mktemp -t asc_key)"
mv "$KEYFILE" "$KEYFILE.p8"
KEYFILE="$KEYFILE.p8"
ZIPDIR=""
trap 'rm -f "$KEYFILE"; [[ -n "$ZIPDIR" ]] && rm -rf "$ZIPDIR"' EXIT
printf '%s\n' "$ASC_KEY_P8" > "$KEYFILE"
AUTH=(--key "$KEYFILE" --key-id "$ASC_KEY_ID" --issuer "$ASC_ISSUER_ID")

# notarytool only accepts archives (.zip/.dmg/.pkg), while stapler only
# accepts the thing the ticket belongs to — a bundle or an image, never a
# zip. So an .app is zipped for submission and stapled in place afterwards;
# a .dmg is both submitted and stapled directly.
SUBMIT="$TARGET"
if [[ "$TARGET" == *.app ]]; then
  ZIPDIR="$(mktemp -d)"
  SUBMIT="$ZIPDIR/$(basename "$TARGET").zip"
  ditto -c -k --keepParent "$TARGET" "$SUBMIT"
fi

# notarytool can exit 0 even when the verdict is Invalid, so the status line
# is checked explicitly and the per-file log is fetched on any non-Accepted.
echo "▸ Notarizing $TARGET (this can take a few minutes)…"
OUT="$(xcrun notarytool submit "$SUBMIT" "${AUTH[@]}" --wait 2>&1 | tee /dev/stderr)"
SUBMISSION_ID="$(sed -nE 's/^[[:space:]]*id: ([0-9a-f-]+)$/\1/p' <<<"$OUT" | head -n 1)"
if ! grep -q "status: Accepted" <<<"$OUT"; then
  echo "✗ notarization not accepted — notary log:" >&2
  [[ -n "$SUBMISSION_ID" ]] && xcrun notarytool log "$SUBMISSION_ID" "${AUTH[@]}" >&2 || true
  exit 1
fi

echo "▸ Stapling ticket…"
xcrun stapler staple "$TARGET"
xcrun stapler validate "$TARGET"
echo "✅ Notarized + stapled → $TARGET"
