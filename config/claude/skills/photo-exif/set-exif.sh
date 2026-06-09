#!/usr/bin/env bash
# set-exif.sh — backfill EXIF on a batch of (usually film-scanned) JPEGs.
#
# Applies a camera + lens preset from cameras.json, sequenced DateTimeOriginal
# (so Photos.app imports them in order), and GPS. exiftool keeps _original
# backups by default, so edits are reversible.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRESETS="$SKILL_DIR/cameras.json"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] FILE...

Options:
  --camera KEY      camera preset key from cameras.json
  --lens KEY        lens preset key from cameras.json
  --film KEY        film preset key from cameras.json (writes Keywords + UserComment)
  --date "YYYY-MM-DD HH:MM:SS"   base DateTimeOriginal
  --step N          seconds between consecutive files (default: 1)
  --tz "+HH:MM"     timezone offset for OffsetTimeOriginal (e.g. "+02:00")
  --gps "LAT,LON"   decimal coordinates (negative = S/W)
  --location KEY    location preset from locations.local.json (gitignored)
  --no-backup       pass exiftool -overwrite_original (no _original files)
  --dry-run         print exiftool commands without running them

Files are processed in the order given. With --date and --step 1, the first
file gets DateTimeOriginal=DATE, second gets DATE+1s, etc.

Presets available:
EOF
  if [[ -f "$PRESETS" ]]; then
    jq -r '.cameras | to_entries[] | "  --camera \(.key)   \(.value.description)"' "$PRESETS"
    jq -r '.lenses  | to_entries[] | "  --lens   \(.key)   \(.value.description)"' "$PRESETS"
    jq -r '.films   | to_entries[]? | "  --film   \(.key)   \(.value.description)"' "$PRESETS"
  fi
}

CAMERA=""
LENS=""
FILM=""
DATE_BASE=""
STEP=1
TZ_OFFSET=""
GPS=""
LOCATION=""
NO_BACKUP=0
DRY_RUN=0
FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --camera) CAMERA="$2"; shift 2 ;;
    --lens) LENS="$2"; shift 2 ;;
    --film) FILM="$2"; shift 2 ;;
    --date) DATE_BASE="$2"; shift 2 ;;
    --step) STEP="$2"; shift 2 ;;
    --tz) TZ_OFFSET="$2"; shift 2 ;;
    --gps) GPS="$2"; shift 2 ;;
    --location) LOCATION="$2"; shift 2 ;;
    --no-backup) NO_BACKUP=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --) shift; while [[ $# -gt 0 ]]; do FILES+=("$1"); shift; done ;;
    -*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) FILES+=("$1"); shift ;;
  esac
done

if [[ ${#FILES[@]} -eq 0 ]]; then
  usage >&2
  exit 1
fi

# Validate preset keys early
if [[ -n "$CAMERA" ]] && ! jq -e --arg k "$CAMERA" '.cameras[$k]' "$PRESETS" >/dev/null; then
  echo "Unknown camera preset: $CAMERA" >&2; exit 1
fi
if [[ -n "$LENS" ]] && ! jq -e --arg k "$LENS" '.lenses[$k]' "$PRESETS" >/dev/null; then
  echo "Unknown lens preset: $LENS" >&2; exit 1
fi
if [[ -n "$FILM" ]] && ! jq -e --arg k "$FILM" '.films[$k]' "$PRESETS" >/dev/null; then
  echo "Unknown film preset: $FILM" >&2; exit 1
fi

# Resolve --location → GPS via locations.local.json (kept out of git)
if [[ -n "$LOCATION" ]]; then
  if [[ -n "$GPS" ]]; then
    echo "--gps and --location are mutually exclusive" >&2; exit 1
  fi
  LOCATIONS_FILE="$SKILL_DIR/locations.local.json"
  if [[ ! -f "$LOCATIONS_FILE" ]]; then
    echo "No locations.local.json next to the script — create one to use --location" >&2; exit 1
  fi
  if ! jq -e --arg k "$LOCATION" '.locations[$k]' "$LOCATIONS_FILE" >/dev/null; then
    echo "Unknown location preset: $LOCATION" >&2; exit 1
  fi
  GPS=$(jq -r --arg k "$LOCATION" '.locations[$k] | "\(.lat),\(.lon)"' "$LOCATIONS_FILE")
fi

# Build args that are identical for every file (camera, lens, GPS).
# `-m` tolerates minor errors (e.g. malformed MakerNotes in scans) — without it,
# exiftool refuses to write when any tag is suspect.
COMMON_ARGS=("-m")
[[ "$NO_BACKUP" == 1 ]] && COMMON_ARGS+=("-overwrite_original")

if [[ -n "$CAMERA" ]]; then
  while IFS=$'\t' read -r tag val; do
    COMMON_ARGS+=("-$tag=$val")
  done < <(jq -r --arg k "$CAMERA" '.cameras[$k].exif | to_entries[] | "\(.key)\t\(.value)"' "$PRESETS")
fi

if [[ -n "$LENS" ]]; then
  while IFS=$'\t' read -r tag val; do
    COMMON_ARGS+=("-$tag=$val")
  done < <(jq -r --arg k "$LENS" '.lenses[$k].exif | to_entries[] | "\(.key)\t\(.value)"' "$PRESETS")
fi

if [[ -n "$FILM" ]]; then
  while IFS=$'\t' read -r tag val; do
    COMMON_ARGS+=("-$tag=$val")
  done < <(jq -r --arg k "$FILM" '.films[$k].exif | to_entries[] | "\(.key)\t\(.value)"' "$PRESETS")
fi

if [[ -n "$GPS" ]]; then
  LAT="${GPS%,*}"
  LON="${GPS#*,}"
  LAT="${LAT## }"; LAT="${LAT%% }"
  LON="${LON## }"; LON="${LON%% }"
  LAT_REF="N"; LON_REF="E"
  [[ "$LAT" == -* ]] && { LAT_REF="S"; LAT="${LAT#-}"; }
  [[ "$LON" == -* ]] && { LON_REF="W"; LON="${LON#-}"; }
  COMMON_ARGS+=(
    "-GPSLatitude=$LAT"
    "-GPSLatitudeRef=$LAT_REF"
    "-GPSLongitude=$LON"
    "-GPSLongitudeRef=$LON_REF"
  )
fi

# Per-file pass: apply common args + the sequenced date
idx=0
for f in "${FILES[@]}"; do
  per_file=("${COMMON_ARGS[@]}")
  if [[ -n "$DATE_BASE" ]]; then
    OFFSET_SEC=$((idx * STEP))
    NEW_DATE=$(date -j -v+${OFFSET_SEC}S -f "%Y-%m-%d %H:%M:%S" "$DATE_BASE" "+%Y:%m:%d %H:%M:%S")
    per_file+=("-DateTimeOriginal=$NEW_DATE" "-CreateDate=$NEW_DATE")
    if [[ -n "$TZ_OFFSET" ]]; then
      per_file+=("-OffsetTimeOriginal=$TZ_OFFSET" "-OffsetTimeDigitized=$TZ_OFFSET")
    fi
  fi
  if [[ "$DRY_RUN" == 1 ]]; then
    printf 'exiftool'
    printf ' %q' "${per_file[@]}" "$f"
    printf '\n'
  else
    # Don't let one bad file abort the whole batch (set -e otherwise would).
    exiftool "${per_file[@]}" "$f" || echo "  ERR: $(basename "$f") (exiftool exit $?)" >&2
  fi
  idx=$((idx + 1))
done
