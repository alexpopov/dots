#!/bin/bash

# ffmpeg_shortcuts.sh - Resize video to specified height
# Usage: ffmpeg_shortcuts.sh input_file [height]

if [ $# -lt 1 ]; then
    echo "Usage: $0 input_file [height]"
    echo "  input_file: Path to the input video file"
    echo "  height:     Target height in pixels (default: 480)"
    exit 1
fi

INPUT="$1"
HEIGHT="${2:-480}"  # Default to 480 if not provided

# Check if input file exists
if [ ! -f "$INPUT" ]; then
    echo "Error: Input file '$INPUT' not found"
    exit 1
fi

# Get directory and filename without extension
DIR=$(dirname "$INPUT")
FILENAME=$(basename "$INPUT")
NAME="${FILENAME%.*}"

# Output filename with height suffix
OUTPUT="${DIR}/${NAME}_${HEIGHT}.mp4"

echo "Converting: $INPUT"
echo "Output: $OUTPUT"
echo "Height: ${HEIGHT}px (width will scale proportionally)"

ffmpeg -i "$INPUT" -vf "scale=-2:${HEIGHT}" -c:v libx264 -preset fast -crf 23 -c:a aac -b:a 128k -movflags +faststart "$OUTPUT"
