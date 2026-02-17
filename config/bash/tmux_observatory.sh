# vi: ft=bash
# Tmux pane observatory: broadcast pane output and watch it from another session.
#
# Usage:
#   tmux-broadcast [description]   - start piping this pane (re-run to update description)
#   tmux-stop-broadcast            - stop piping and clean up
#   tmux-watch                     - pick a broadcast to tail (label in tmux pane border)

TMUX_OBSERVATORY_DIR="$HOME/.local/share/tmux/observatory"

function tmux-broadcast {
  if [[ -z "$TMUX" ]]; then
    echo "Not in a tmux session" >&2
    return 1
  fi
  local desc="$*"
  local win_name pane_idx pipe_file desc_file
  win_name=$(tmux display-message -p '#{window_name}')
  pane_idx=$(tmux display-message -p '#{pane_index}')
  pipe_file="$TMUX_OBSERVATORY_DIR/${win_name}-${pane_idx}.pipe"
  desc_file="${pipe_file%.pipe}.desc"
  mkdir -p "$TMUX_OBSERVATORY_DIR"
  if [[ -f "$pipe_file" ]]; then
    if [[ -n "$desc" ]]; then
      echo "$desc" > "$desc_file"
      echo "Updated description: $desc"
    else
      echo "Already broadcasting this pane" >&2
    fi
    return 0
  fi
  printf '=== %s | window: %s | pane: %s | %s ===\n' \
    "$(tmux display-message -p '#{session_name}')" \
    "$win_name" "$pane_idx" "$(date '+%Y-%m-%d %H:%M')" > "$pipe_file"
  [[ -n "$desc" ]] && echo "$desc" > "$desc_file"
  tmux pipe-pane -o "cat >> '${pipe_file}'"
  echo "Broadcasting to observatory: ${win_name}-${pane_idx}.pipe"
}

function tmux-stop-broadcast {
  if [[ -z "$TMUX" ]]; then
    echo "Not in a tmux session" >&2
    return 1
  fi
  local win_name pane_idx pipe_file
  win_name=$(tmux display-message -p '#{window_name}')
  pane_idx=$(tmux display-message -p '#{pane_index}')
  pipe_file="$TMUX_OBSERVATORY_DIR/${win_name}-${pane_idx}.pipe"
  if [[ ! -f "$pipe_file" ]]; then
    echo "This pane is not broadcasting" >&2
    return 1
  fi
  tmux pipe-pane
  rm -f "$pipe_file" "${pipe_file%.pipe}.desc"
  echo "Stopped broadcasting: ${win_name}-${pane_idx}"
}

function tmux-watch {
  local pipe_file
  local files=()
  for f in "$TMUX_OBSERVATORY_DIR"/*.pipe; do
    [[ -e "$f" ]] && files+=("$f")
  done
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "No observatory pipes found in $TMUX_OBSERVATORY_DIR" >&2
    return 1
  fi
  pipe_file=$(printf '%s\n' "${files[@]}" | xargs -n1 basename | \
    fzf --preview "f='$TMUX_OBSERVATORY_DIR/{}'; d=\"\${f%.pipe}.desc\"; [ -f \"\$d\" ] && echo \"[\$(cat \"\$d\")]\" && echo; tail -5 \"\$f\"")
  [[ -z "$pipe_file" ]] && return 0
  local full_path="$TMUX_OBSERVATORY_DIR/$pipe_file"
  local label="${pipe_file%.pipe}"
  local desc_file="$TMUX_OBSERVATORY_DIR/${label}.desc"
  [[ -f "$desc_file" ]] && label="$label — $(cat "$desc_file")"
  # Set tmux pane border to show the label
  if [[ -n "$TMUX" ]]; then
    tmux set-option -w pane-border-status bottom 2>/dev/null
    tmux select-pane -T "$label"
    tmux set-option -w pane-border-format " #{pane_title} " 2>/dev/null
  fi
  tail -f "$full_path" | sed -u 's/\x1b\][0-2];[^\x07]*\x07//g; s/\x1b\][0-2];[^\x1b]*\x1b\\//g'
  tput cnorm 2>/dev/null
  read -rp "Delete ${pipe_file}? [y/N] " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    rm -f "$full_path" "${full_path%.pipe}.desc"
    echo "Deleted $pipe_file"
  fi
}
