#!/usr/bin/env bash
# tmux-rearm-after-reload — re-applied ~8s after every config reload, once the
# tpm/plugin churn has settled. Plain shell file deliberately: the equivalent
# inline run-shell one-liner kept getting mangled by tmux's own parser
# (`#FFC600` lost its `#F`, styles rejected). Does three things:
#   1. Re-add continuum's #(save.sh) status-right hook if a reload wiped it
#      (continuum skips re-adding it on live servers).
#   2. Re-apply the Cobalt2 message styles incl. full-width fill (the jimeh
#      theme Apply overwrites them without fill on reload).
#   3. Re-apply the gold-bold active-tab style (same clobber reason).
sleep 8
tmux show -gqv status-right | grep -q continuum_save || tmux set-option -g status-right "#(~/.tmux/plugins/tmux-continuum/scripts/continuum_save.sh)$(tmux show -gqv status-right)"
tmux set-option -g message-style "fg=white,bg=#193549,fill=#193549"
tmux set-option -g message-command-style "fg=white,bg=#193549,fill=#193549"
tmux set-option -gw window-status-current-style "fg=#193549,bg=#FFBE33,bold"
