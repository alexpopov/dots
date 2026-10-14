#!/bin/bash

session="Main"
window_yabai="yabai"

t_window_yabai="$session:1"

# Build "Main" from scratch only if it isn't there. The layout and the
# send-keys have to stay inside this guard: tmux-continuum restores this
# session automatically on a cold server start, and firing send-keys at a
# session we didn't create would type into whatever panes happen to sit at
# those indices. Starting skhd/yabai is handled outside the guard by
# tmux-ensure-wm, which checks whether they're running rather than whether
# we just built the session -- a restored session has the panes but no
# window manager in them.
if ! tmux has-session -t "$session" 2>/dev/null; then
  # create the session
  tmux new-session -d -s "$session"

  tmux rename-window -t "$session:1" "$window_yabai"
  tmux split-window -h  # implicitly the first window
  tmux split-window -v -t "$session:1.0"
  tmux split-window -v -t "$session:1.2"

  # Now the panes are numbered:
  # [ 0 | 2 ]
  # [ 1 | 3 ]
  #
  # Set up as follows:
  # 0: skhd
  # 1: yabai
  # 2: dots vim
  # 3: dots dir

  tmux send-keys -t "$t_window_yabai.2" 'cd dots; vim config/nvim/lua/lua_init.lua' C-m
  tmux send-keys -t "$t_window_yabai.3" 'cd dots' C-m
fi

# Panes 0 and 1 of the yabai window, whether we just made them or continuum
# restored them empty. No-op when skhd/yabai are already running.
"$(dirname "${BASH_SOURCE[0]}")/tmux-ensure-wm"

tmux a -t "$session"

