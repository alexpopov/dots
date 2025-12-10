#!/bin/bash
# Explain AOSP build errors with Claude or DMT

SCRIPT_NAME="$(basename "$0")"
if [[ "$SCRIPT_NAME" == dmt_* ]]; then
    CMD="dmt"
else
    CMD="claude"
fi

if [[ -z "$ANDROID_BUILD_TOP" ]]; then
    echo "Error: ANDROID_BUILD_TOP is not set."
    echo "Run 'source build/envsetup.sh && lunch <target>' first."
    exit 1
fi

ERROR_LOG="$ANDROID_BUILD_TOP/out/error.log"

if [[ ! -f "$ERROR_LOG" ]]; then
    echo "Error: $ERROR_LOG does not exist."
    echo "No build errors logged yet, or build hasn't been run."
    exit 1
fi

BLUE='\033[34m'
GREEN='\033[32m'
RESET='\033[0m'

PROMPT="I was building in AOSP and ran into an error. Device: $TARGET_PRODUCT, Build variant: $TARGET_BUILD_VARIANT. Read $ERROR_LOG and explain it to me."

echo -e "Starting ${BLUE}$CMD${RESET} with: ${GREEN}\"$PROMPT\"${RESET}"
$CMD "$PROMPT"
