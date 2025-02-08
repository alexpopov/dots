#!/bin/bash

session="Main"
window_yabai="yabai"

t_window_yabai="$session:1"

if ! tmux has-session -t "$session" 2>/dev/null; then
  # create the session
  tmux new-session -d -s "$session"

  tmux rename-window -t "$session:1" "$window_yabai"
  tmux split-window -h  # implicitly the first window
  tmux split-window -v -t "$session:1.0"
  tmux split-window -v -t "$session:1.2"
fi

# tmux attach -t "$session"

# Now the panes are numbered:
# [ 0 | 2 ]
# [ 1 | 3 ]
#
# Set up as follows:
# 0: skhd
# 1: yabai
# 2: dots vim
# 3: dots dir

tmux send-keys -t "$t_window_yabai.0" '$(which skhd) --config ~/dots/config/skhd/skhdrc' C-m
tmux send-keys -t "$t_window_yabai.1" 'yabai' C-m
tmux send-keys -t "$t_window_yabai.2" 'cd dots; vim config/nvim/lua/lua_init.lua' C-m
tmux send-keys -t "$t_window_yabai.3" 'cd dots' C-m



# # In Pane 1
# tmux split-window -t "$t_window_yabai" -h # split into left and right
# # In Pane 2
# tmux send-keys -t "$t_window_yabai" 'cd ~/dots/; nvim' Enter

# # Pane 1
# tmux select-pane -t 0
# tmux split-window -v
# # Pane C
# tmux send-keys -t "$t_window_yabai" 'yabai' Enter
# tmux select-pane -t
# tmux split-window -t "$t_window_yabai" -v
