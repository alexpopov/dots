# vi: ft=bash
# Tmux pane observatory: broadcast pane output and watch it from another session.
#
# Usage:
#   tmux-broadcast [description]   - start piping this pane (re-run to update description)
#   tmux-stop-broadcast            - stop piping and clean up
#   tmux-watch                     - pick a broadcast to tail (label in tmux pane border)
#   tmux-watch all                 - open all broadcasts in a grid of tmux splits

TMUX_OBSERVATORY_DIR="$HOME/.local/share/tmux/observatory"

# Shared sed filter for stripping escape sequences and Claude Code UI chars
_OBSERVATORY_SED_FILTER='s/\x1b\][0-2];[^\x07]*\x07//g; s/\x1b\][0-2];[^\x1b]*\x1b\\//g; s/❯//g; s/─\{3,\}//g'

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
  local files=()
  for f in "$TMUX_OBSERVATORY_DIR"/*.pipe; do
    [[ -e "$f" ]] && files+=("$f")
  done
  if [[ ${#files[@]} -eq 0 ]]; then
    echo "No observatory pipes found in $TMUX_OBSERVATORY_DIR" >&2
    return 1
  fi

  if [[ "$1" == "all" ]]; then
    _tmux_watch_all "${files[@]}"
    return $?
  fi

  local pipe_file
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
  tail -f "$full_path" | sed -u "$_OBSERVATORY_SED_FILTER"
  tput cnorm 2>/dev/null
  read -rp "Delete ${pipe_file}? [y/N] " answer
  if [[ "$answer" =~ ^[Yy]$ ]]; then
    rm -f "$full_path" "${full_path%.pipe}.desc"
    echo "Deleted $pipe_file"
  fi
}

function _tmux_watch_all {
  local files=("$@")
  local n=${#files[@]}

  # List what we'll open
  echo "Opening $n broadcasts:"
  for f in "${files[@]}"; do
    local name=$(basename "$f" .pipe)
    local desc_file="${f%.pipe}.desc"
    if [[ -f "$desc_file" ]]; then
      echo "  $name — $(cat "$desc_file")"
    else
      echo "  $name"
    fi
  done
  read -rp "Continue? [Y/n] " answer
  [[ "$answer" =~ ^[Nn]$ ]] && return 0

  # Calculate grid: cols x rows where cols >= rows, cols * rows >= n
  local cols=1 rows=1
  while (( cols * rows < n )); do
    if (( cols <= rows )); then
      (( cols++ ))
    else
      (( rows++ ))
    fi
  done

  # Set up pane borders for the window
  tmux set-option -w pane-border-status bottom 2>/dev/null
  tmux set-option -w pane-border-format " #{pane_title} " 2>/dev/null

  # Build the watch command template
  local watch_cmd="tail -f {} | sed -u '$_OBSERVATORY_SED_FILTER'"

  # First file runs in the current pane
  local first_file="${files[0]}"
  local first_name=$(basename "$first_file" .pipe)
  local first_desc_file="${first_file%.pipe}.desc"
  local first_label="$first_name"
  [[ -f "$first_desc_file" ]] && first_label="$first_name — $(cat "$first_desc_file")"

  # Create horizontal splits for rows, then vertical splits within each row
  # Strategy: split into $rows horizontal bands, then split each band into $cols
  local pane_ids=()
  pane_ids+=($(tmux display-message -p '#{pane_id}'))

  # Create row splits (horizontal)
  for (( r = 1; r < rows; r++ )); do
    local pct=$(( 100 - 100 / (rows - r + 1) ))
    pane_ids+=($(tmux split-window -v -p "$pct" -P -F '#{pane_id}'))
  done

  # For each row, create column splits (vertical)
  local all_panes=()
  for (( r = 0; r < rows; r++ )); do
    local row_pane="${pane_ids[$r]}"
    all_panes+=("$row_pane")
    for (( c = 1; c < cols; c++ )); do
      local pct=$(( 100 - 100 / (cols - c + 1) ))
      all_panes+=($(tmux split-window -h -t "$row_pane" -p "$pct" -P -F '#{pane_id}'))
    done
  done

  # Send watch commands to each pane
  for (( i = 0; i < n; i++ )); do
    local file="${files[$i]}"
    local pane="${all_panes[$i]}"
    local name=$(basename "$file" .pipe)
    local desc_file="${file%.pipe}.desc"
    local label="$name"
    [[ -f "$desc_file" ]] && label="$name — $(cat "$desc_file")"

    tmux select-pane -t "$pane" -T "$label"
    if (( i == 0 )); then
      # Current pane — run directly
      tmux send-keys -t "$pane" "tail -f '$file' | sed -u '$_OBSERVATORY_SED_FILTER'" Enter
    else
      tmux send-keys -t "$pane" "tail -f '$file' | sed -u '$_OBSERVATORY_SED_FILTER'" Enter
    fi
  done
}
