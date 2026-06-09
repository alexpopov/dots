#!/usr/bin/env bash
# set-location.sh — set GPS on currently-selected Photos.app photos.
# Supply coordinates inline (--gps) or by named preset (--location).
# Presets live in locations.local.json next to this script (gitignored).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCATIONS_FILE="$SCRIPT_DIR/locations.local.json"

usage() {
  cat <<EOF >&2
Usage: $(basename "$0") (--gps LAT,LON | --location KEY)

  --gps LAT,LON   decimal coordinates (negative = S/W)
  --location KEY  preset key from locations.local.json (gitignored)

Presets:
EOF
  if [[ -f "$LOCATIONS_FILE" ]]; then
    jq -r '.locations | to_entries[] | "  --location \(.key)   \(.value.description // "(no description)")"' "$LOCATIONS_FILE" >&2
  fi
  exit 1
}

GPS=""
LOCATION=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --gps) GPS="$2"; shift 2 ;;
    --location) LOCATION="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown: $1" >&2; usage ;;
  esac
done

if [[ -n "$LOCATION" ]]; then
  [[ -n "$GPS" ]] && { echo "--gps and --location are mutually exclusive" >&2; exit 1; }
  [[ -f "$LOCATIONS_FILE" ]] || { echo "No $LOCATIONS_FILE — create one to use --location" >&2; exit 1; }
  if ! jq -e --arg k "$LOCATION" '.locations[$k]' "$LOCATIONS_FILE" >/dev/null; then
    echo "Unknown location preset: $LOCATION" >&2; exit 1
  fi
  GPS=$(jq -r --arg k "$LOCATION" '.locations[$k] | "\(.lat),\(.lon)"' "$LOCATIONS_FILE")
fi

[[ -z "$GPS" ]] && usage

LAT="${GPS%,*}"
LON="${GPS#*,}"

: "${UV_CACHE_DIR:=$HOME/dots/.uv-cache-tmp}"
export UV_CACHE_DIR

echo "=== Before ==="
"$SCRIPT_DIR/show-selected.sh"

echo
echo "=== Setting location to $LAT, $LON ==="
# Pipe /dev/null into stdin — batch-edit blocks on stdin EOF in non-tty
# environments. With </dev/null the command exits cleanly.
uvx --quiet osxphotos batch-edit --location "$LAT" "$LON" </dev/null 2>&1 | tail -3

echo
echo "=== After ==="
"$SCRIPT_DIR/show-selected.sh"

[[ -f "$PWD/osxphotos_crash.log" ]] && rm -f "$PWD/osxphotos_crash.log"
