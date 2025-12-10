#!/bin/bash
# Helper for tmux Claude binding
# Prompts for instructions, saves both to temp files, types command into terminal

INSTRUCTIONS_FILE="/tmp/tmux_claude_instructions.txt"
SELECTION_FILE="/tmp/tmux_claude_selection.txt"

read -rp "Instructions: " INSTRUCTIONS
echo "$INSTRUCTIONS" > "$INSTRUCTIONS_FILE"

tmux send-keys "claude 'Read $INSTRUCTIONS_FILE for instructions, then read $SELECTION_FILE and follow the instructions'"
