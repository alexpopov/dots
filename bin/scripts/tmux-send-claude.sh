#!/usr/bin/env bash
# tmux-send-claude — menu-driven twin of the old copy-mode-vi `C` binding
# (binding removed; menu-only now). Yanks the copy-mode selection, stashes
# it, and prompts for instructions via tmux_claude.sh. Opened from the menu
# with no selection active, it says so instead of failing silently.
if [ "$(tmux display-message -p '#{pane_in_mode}')" = 1 ]; then
  tmux send-keys -X copy-selection-and-cancel
  tmux save-buffer /tmp/tmux_claude_selection.txt
  tmux send-keys "$HOME/.local/bin/scripts/tmux_claude.sh" Enter
else
  tmux display-message 'no selection: enter copy-mode + select first (prefix /), then prefix-i'
fi
