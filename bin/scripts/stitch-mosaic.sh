#!/usr/bin/env bash
#
# stitch-mosaic.sh — flat-art / copy-stand mosaic stitcher using Hugin's CLI tools.
#
# Usage: stitch-mosaic.sh <output-prefix> <tile1.tif> <tile2.tif> [tile3.tif ...]
#
# Example: stitch-mosaic.sh my_negative tile_{1..4}.tif
#   → produces my_negative.tif in the current directory
#
# Assumes:
# - All input tiles share one rectilinear lens (auto-detected from EXIF)
# - The mosaic is planar — camera fixed, subject moved (e.g. DSLR copy stand)
# - Tools are at ~/Development/hugin-prefix/bin (built from SourceForge hg source;
#   the homebrew cask is deprecated and x86_64-only)
#
# Pipeline:
#   pto_gen          → seed project from input EXIF
#   cpfind --multirow → detect control points across grid (not just a strip)
#   cpclean          → drop CP outliers
#   pto_var --opt TrX,TrY → mark camera-translation params for optimization
#                          (anchor image's translation stays pinned)
#   autooptimiser -n → run optimizer with the marked vars only
#   pano_modify      → rectilinear projection, auto fov / canvas / crop
#   hugin_executor   → run nona (remap) + enblend (blend) to final TIFF

set -euo pipefail

HUGIN_BIN="$HOME/Development/hugin-prefix/bin"

if [ $# -lt 3 ]; then
    echo "Usage: $(basename "$0") <output-prefix> <tile1.tif> <tile2.tif> [tile3.tif ...]" >&2
    exit 1
fi

PREFIX="$1"
shift
TILES=("$@")

PTO=$(mktemp -t mosaic.XXXXXX).pto
trap 'rm -f "$PTO"' EXIT

export PATH="$HUGIN_BIN:$PATH"

echo ">> seeding project from ${#TILES[@]} tiles"
pto_gen -o "$PTO" "${TILES[@]}"

echo ">> finding control points (--multirow for grid layout)"
cpfind --multirow -o "$PTO" "$PTO"

echo ">> cleaning CP outliers"
cpclean -o "$PTO" "$PTO"

echo ">> marking TrX,TrY for optimization (anchor stays pinned)"
pto_var --opt "TrX,TrY" -o "$PTO" "$PTO"

echo ">> optimizing translation"
autooptimiser -n -o "$PTO" "$PTO"

echo ">> rectilinear projection + auto canvas/crop"
pano_modify --projection=0 --fov=AUTO --canvas=AUTO --crop=AUTO -o "$PTO" "$PTO"

echo ">> stitching → ${PREFIX}.tif"
hugin_executor --stitching --prefix="$PREFIX" "$PTO"

echo "done: ${PREFIX}.tif"
