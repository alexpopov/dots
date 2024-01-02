#!/usr/bin/env bash

INPUT_VIDEO="$1"
shift

OUTPUT_FOLDER="$1"
shift

FRAME_SKIP="$1"
shift

if [[ -z $OUTOUT_FOLDER || -z $INPUT_VIDEO ]]; then
  echo "error: missing argument"
  echo "usage: INPUT_VIDEO OUTPUT_FOLDER N"
  echo "    where 'n' is how many frames to skip"
  exit 1
fi

read -p "Extract frames? " -n 1 -r
echo    # (optional) move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]; then
  # select every nth frame and output to folder
  ffmpeg -i "$1" -vf "select=not(mod(n\,$FRAME_SKIP))" -vsync vfr "$OUTPUT_FOLDER"/still_%06d.png
else
  echo "goodbye"
  exit 0
fi


read -p "Increase saturation and brightness? " -n 1 -r
echo    # (optional) move to a new line
if [[ $REPLY =~ ^[Yy]$ ]]; then
  # for every file
  # parallelize 8x
  # increase brightness by 20
  # increase contrast by 50
  # (who knows what these units are)
  # note: we only do this because the input video was HDR and the extracted frames are dim and desatured
  # we output to jpeg because lossless PNGs from 4K are *massive*
  # imagemagick is great
  find "$OUTPUT_FOLDER" -type f | xargs -I{} -n 1 -P 8 convert -brightness-contrast 20x50 {} -quality 90 {}_fixed.jpeg
else
  echo "goodbye"
  exit 0
fi
