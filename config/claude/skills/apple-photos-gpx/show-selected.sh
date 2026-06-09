#!/usr/bin/env bash
# show-selected.sh — terse summary of currently-selected photos in Photos.app.
# Sorted by date. Columns: filename, ISO date (with offset), TZ name, GPS or "—".
set -euo pipefail

: "${UV_CACHE_DIR:=$HOME/dots/.uv-cache-tmp}"
export UV_CACHE_DIR

{
  printf 'FILE\tDATE\tTZ\tGPS\n'
  uvx --quiet osxphotos query --selected --json 2>/dev/null \
    | jq -r '
        .[] |
        [ .original_filename,
          .date,
          .tzname,
          if .latitude then "\(.latitude),\(.longitude)" else "—" end
        ] | @tsv
      ' \
    | sort -k2
} | column -t -s $'\t'
