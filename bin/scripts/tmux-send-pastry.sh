#!/usr/bin/env bash
# tmux-send-pastry — menu-driven twin of the old copy-mode-vi `P` binding
# (binding removed; menu-only now). Yanks the copy-mode selection and pipes
# it to pastry. Opened from the menu with no selection active, it says so
# instead of failing silently.
if [ "$(tmux display-message -p '#{pane_in_mode}')" = 1 ]; then
  tmux send-keys -X copy-selection-and-cancel
  tmux save-buffer /tmp/tmux_pastry_selection.txt
  tmux send-keys "pastry < /tmp/tmux_pastry_selection.txt" Enter
else
  tmux display-message 'no selection: enter copy-mode + select first (prefix /), then prefix-i'
fi
