#!/usr/bin/env bash
# resurrect-pretype-claude.sh: after a tmux-resurrect restore, type each saved
# Claude Code pane's resume command into that pane WITHOUT pressing Enter, so a
# human decides whether to resume it.
#
# Wired up as @resurrect-hook-post-restore-all in config/tmux/tmux.conf. Claude
# is deliberately not in @resurrect-processes: that would run it straight away.
#
#   resurrect-pretype-claude.sh [save-file]    # default: resurrect's "last" save

set -euo pipefail

save_file="${1:-}"
if [[ -z "$save_file" ]]; then
    # Same lookup as tmux-resurrect's helpers.sh: @resurrect-dir, else
    # ~/.tmux/resurrect if it exists, else the XDG data dir.
    dir="$(tmux show-option -gqv @resurrect-dir)"
    if [[ -z "$dir" ]]; then
        if [[ -d "$HOME/.tmux/resurrect" ]]; then
            dir="$HOME/.tmux/resurrect"
        else
            dir="${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect"
        fi
    fi
    dir="${dir/#\~/$HOME}"
    save_file="$dir/last"
fi
[[ -r "$save_file" ]] || { echo "resurrect-pretype-claude.sh: no save file at $save_file" >&2; exit 0; }

# pane lines are tab-separated:
#   pane session window win_active win_flags pane_index title :dir pane_active cmd :full_command
while IFS=$'\t' read -r kind session window _ _ pane _ _ _ _ full; do
    [[ "$kind" == "pane" ]] || continue
    full="${full#:}"
    # The resolved binary, e.g. /usr/local/bin/claude_code/claude --resume <id>
    [[ "$full" == *claude_code/claude || "$full" == *claude_code/claude\ * ]] || continue

    args="${full#*claude_code/claude}"
    args="${args# }"
    # A pane started as plain `claude` has no session id on its command line;
    # --continue picks up the most recent session in the pane's directory.
    case " $args " in
        *" --resume "*|*" -r "*|*" --continue "*|*" -c "*) cmd="claude $args" ;;
        *) cmd="claude --continue${args:+ $args}" ;;
    esac

    tmux send-keys -t "${session}:${window}.${pane}" -l "$cmd" 2>/dev/null \
        || echo "resurrect-pretype-claude.sh: pane ${session}:${window}.${pane} is gone" >&2
done < "$save_file"
