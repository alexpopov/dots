#!/bin/bash

session="Main"
window_yabai="yabai"

t_window_yabai="=$session:=$window_yabai"

tmux new-session -d -s "$session" -n "$window_yabai"

tmux rename-window -t "$t_window_yabai" "yabai"

# [ A | B ]
# [ C | D ]
#
# A: skhd
# C: yabai
# B: dots vim
# D: dots dir

# Pane B
tmux split-window -t "$t_window_yabai" -h
tmux send-keys -t "$t_window_yabai" 'cd ~/dots/; nvim' Enter
tmux split-window -t "$t_window_yabai" -v

# Pane A
tmux select-pane -t 0
tmux send-keys -t "$t_window_yabai" '$(which skhd) --config ~/dots/config/skhd/skhdrc' Enter
tmux split-window -v
# Pane C
tmux send-keys -t "$t_window_yabai" 'yabai' Enter
