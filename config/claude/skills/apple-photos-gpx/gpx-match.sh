#!/usr/bin/env bash
# gpx-match.sh — thin wrapper around gpx-match.py via `osxphotos run`.
# Forwards all args to the Python script.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec osxphotos run "$SCRIPT_DIR/gpx-match.py" "$@"
