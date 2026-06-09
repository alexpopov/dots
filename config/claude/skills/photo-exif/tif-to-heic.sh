#!/usr/bin/env bash
# tif-to-heic.sh — convert TIF scans to HEIC, downscaling and preserving EXIF.
# sips handles the encode (hardware-accelerated on Apple Silicon) but DROPS
# Keywords/Subject during format conversion. This script does the conversion
# then copies those tags back from the source TIF via exiftool.
#
# Default: max long edge 3840 px (4K), quality 80, parallel 8.
set -euo pipefail

MAX_LONG_EDGE=3840
QUALITY=80
PARALLEL=8
OUT_DIR=""
FILES=()

usage() {
  cat <<EOF >&2
Usage: $(basename "$0") --out DEST_DIR [options] FILE...

Options:
  --out DIR     output directory (required) — mirrors basenames with .heic
  --max N       max long edge in px (default: $MAX_LONG_EDGE)
  --quality Q   HEIC quality 0-100 (default: $QUALITY)
  --parallel N  workers (default: $PARALLEL)

Output files: <DEST_DIR>/<basename>.heic, with sips not upscaling smaller inputs.
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out) OUT_DIR="$2"; shift 2 ;;
    --max) MAX_LONG_EDGE="$2"; shift 2 ;;
    --quality) QUALITY="$2"; shift 2 ;;
    --parallel) PARALLEL="$2"; shift 2 ;;
    -h|--help) usage ;;
    -*) echo "Unknown: $1" >&2; usage ;;
    *) FILES+=("$1"); shift ;;
  esac
done

[[ -z "$OUT_DIR" ]] && { echo "--out is required" >&2; usage; }
[[ ${#FILES[@]} -eq 0 ]] && { echo "no input files" >&2; usage; }

mkdir -p "$OUT_DIR"

convert_one() {
  local in="$1"
  local base
  base=$(basename "${in%.*}")
  local out="$OUT_DIR/$base.heic"

  # 1. sips: resize + encode
  if ! sips -Z "$MAX_LONG_EDGE" -s format heic -s formatOptions "$QUALITY" \
       "$in" --out "$out" >/dev/null 2>&1; then
    echo " ERR sips: $base" >&2
    return 1
  fi

  # 2. exiftool: copy Keywords/Subject (sips drops these) from source TIF.
  #    -m tolerates minor errors (e.g. malformed MakerNotes in scans).
  exiftool -m -overwrite_original -tagsfromfile "$in" \
    -Keywords -Subject "$out" >/dev/null 2>&1 || true

  local sz
  sz=$(stat -f%z "$out" | awk '{printf "%.1f MB", $1/1024/1024}')
  echo "  ok $base → $sz"
}
export -f convert_one
export OUT_DIR MAX_LONG_EDGE QUALITY

printf '%s\0' "${FILES[@]}" | xargs -0 -n 1 -P "$PARALLEL" bash -c 'convert_one "$0"'
