#!/usr/bin/env bash
# tz-fix.sh CAMERA_TZ ACTUAL_TZ
#
# Two-step osxphotos timewarp on the currently-selected photos in Photos.app:
#   1. --timezone CAMERA_TZ --match-time  (preserve wall clock, fix UTC)
#   2. --timezone ACTUAL_TZ               (preserve UTC, shift wall clock)
#
# Use when a camera was set to one timezone but you were physically in another,
# and Photos.app's TZ guess made the absolute instant wrong.
#
# Example: camera left on Zurich time, you were in Tokyo
#   tz-fix.sh Europe/Zurich Asia/Tokyo
set -euo pipefail

if [[ $# -ne 2 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<EOF >&2
Usage: $(basename "$0") CAMERA_TZ ACTUAL_TZ

  CAMERA_TZ   IANA name of the TZ the camera's clock was set to (e.g. Europe/Zurich)
  ACTUAL_TZ   IANA name of the TZ where the photos were actually taken (e.g. Asia/Tokyo)

Operates on photos currently selected in Photos.app.
EOF
  exit 1
fi

CAMERA_TZ="$1"
ACTUAL_TZ="$2"

: "${UV_CACHE_DIR:=$HOME/dots/.uv-cache-tmp}"
export UV_CACHE_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Before ==="
"$SCRIPT_DIR/show-selected.sh"

echo
echo "=== Step 1: --timezone $CAMERA_TZ --match-time ==="
uvx --quiet osxphotos timewarp --timezone "$CAMERA_TZ" --match-time --force --plain 2>&1 | tail -3

echo
echo "=== Step 2: --timezone $ACTUAL_TZ ==="
uvx --quiet osxphotos timewarp --timezone "$ACTUAL_TZ" --force --plain 2>&1 | tail -3

echo
echo "=== After ==="
"$SCRIPT_DIR/show-selected.sh"

# osxphotos sometimes drops a crash log in $CWD. Don't let it linger in iCloud.
[[ -f "$PWD/osxphotos_crash.log" ]] && rm -f "$PWD/osxphotos_crash.log"
