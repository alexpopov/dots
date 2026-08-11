#!/usr/bin/env bash
# Watch for Stanley entering QFIL / EDL (Sahara) mode = USB 05c6:9008.
# Uses the QFIL package's OWN scanner (lsqdl via IOKit) -> identical match a
# real qfil-flash would use. Announces PRESENT/GONE transitions with a beep.
# Auto-discovers the cached QFIL package so a cache re-download doesn't break it.
#
# Usage:  /tmp/watch_qfil.sh          # poll forever, 1s interval
#         /tmp/watch_qfil.sh 0.5      # custom interval (seconds)
set -u

INTERVAL="${1:-1}"

# Find the newest cached stanley QFIL package dir containing the scanner.
PKG="$(ls -dt "$HOME"/.maui/cache/builds/*-qfil_* "$HOME"/.maui/cache/builds/*qfil* 2>/dev/null \
       | while read -r d; do [ -f "$d/flash_qfil_package.py" ] && { echo "$d"; break; }; done)"

if [ -z "${PKG:-}" ]; then
  echo "ERROR: no cached QFIL package found under ~/.maui/cache/builds/"
  echo "       run:  maui qfil-flash --cache-only -n <build-number>"
  exit 1
fi

# lsqdl / kickstart / fh_loader_darwin are x86_64: clear Gatekeeper quarantine
# once so Rosetta can run them without security prompts (Sequoia+).
xattr -rd com.apple.quarantine "$PKG/lsqdl" 2>/dev/null || true

cd "$PKG" || exit 1
echo "Using package: $PKG"

scan() {
  # authoritative: prints the port list, e.g. "['usb:0x...']" or "[]"
  python3 ./flash_qfil_package.py --test-scan 2>/dev/null \
    | sed -n 's/^QDL Device Found: //p'
}

echo "Watching for Stanley QFIL/EDL (05c6:9008) — Ctrl-C to stop. interval=${INTERVAL}s"
echo "Force it: hold the EDL button-combo / pinhole while plugging into a"
echo "powered port with a known-good full-pin cable."
echo

prev="__init__"
while :; do
  ts="$(date +%T)"
  out="$(scan)"
  if [ "$out" != "[]" ] && [ -n "$out" ]; then
    state="PRESENT"
  else
    state="-"
  fi

  if [ "$state" = "PRESENT" ] && [ "$prev" != "PRESENT" ]; then
    printf '\a'                                   # terminal bell
    echo "$ts  >>> QDL 05c6:9008 PRESENT  ports=$out"
    command -v say >/dev/null && say "Q F I L detected" &
  elif [ "$state" != "PRESENT" ] && [ "$prev" = "PRESENT" ]; then
    echo "$ts  <<< QDL gone (device left EDL / re-enumerated)"
  else
    printf '\r%s  %s      ' "$ts" "$state"        # quiet heartbeat, same line
  fi
  prev="$state"
  sleep "$INTERVAL"
done
