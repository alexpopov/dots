#!/bin/bash
# Explain AOSP build errors with Claude

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

echo -e "Starting ${BLUE}claude${RESET} with: ${GREEN}\"I was building in AOSP and ran into an error. Read ${BLUE}$ERROR_LOG${GREEN} and explain it to me.\"${RESET}"
claude "I was building in AOSP and ran into an error. Read $ERROR_LOG and explain it to me."
