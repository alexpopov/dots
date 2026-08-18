#!/usr/bin/env bash
# ===========================================================================
# copy-pane-cmd.sh — copy the RUNNING command line of a tmux pane's foreground
# program to the clipboard.
#
# Used by tmux.conf's `prefix + y` when the active pane is NOT a shell (e.g.
# picocom, nvim). The normal `prefix + y` grabs the last command + its output
# using OSC-133 prompt marks -- but a foreground program emits no such marks
# and has no shell prompt/output block to bound, so that heuristic walks back
# to some earlier shell command instead (this is the `fastboot getvar serialno`
# bug). For these panes the meaningful thing to yank is the program's own argv,
# which we read straight from the process table -- no screen scraping.
#
#   $1  pane tty (e.g. /dev/ttys018, as tmux's #{pane_tty})
#
# We pick the foreground process (STAT contains '+') on that tty and print its
# full command line, then pipe it through `tmux load-buffer -w -` so it goes
# through server_set_clipboard() and broadcasts OSC-52 to every attached
# client's TTY -- landing on the outer terminal's system clipboard, locally or
# over SSH (same trick as the shell branch in tmux.conf).
# ===========================================================================
set -euo pipefail

tty="${1#/dev/}"

# Foreground process argv. `-o stat=,command=` prints "<stat> <full argv>";
# the STAT field of the pane's foreground process group carries a '+'. Strip
# the STAT column, keep the rest verbatim (internal spacing preserved).
cmd="$(ps -t "$tty" -o stat=,command= 2>/dev/null \
        | awk '$1 ~ /\+/ { sub(/^[^ ]+[ ]+/, ""); print; exit }')"

if [ -z "$cmd" ]; then
    tmux display-message "prefix+y: no foreground command found on $tty"
    exit 0
fi

printf '%s' "$cmd" | tmux load-buffer -w -
tmux display-message "copied running command (${cmd%% *})"
