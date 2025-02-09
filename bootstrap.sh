DOTS_DIR="$HOME/dots/"  # Set this absolute path
DOTS_CONFIG_DIR="$DOTS_DIR/config"
CONFIG_DIR="$HOME/.config"
DOTS_BIN_DIR="$DOTS_DIR/bin"
BIN_DIR="$HOME/.local/bin"

# Make all necessary directories
mkdir -p "$CONFIG_DIR" "$DOTS_CONFIG_DIR" "$BIN_DIR"

ln -sf "$DOTS_CONFIG_DIR/bash" "$CONFIG_DIR"
ln -sf "$DOTS_CONFIG_DIR/input" "$CONFIG_DIR"
ln -sf "$DOTS_CONFIG_DIR/lazygit" "$CONFIG_DIR"
ln -sf "$DOTS_CONFIG_DIR/karabiner" "$CONFIG_DIR"
ln -sf "$DOTS_CONFIG_DIR/nvim" "$CONFIG_DIR"
ln -sf "$DOTS_CONFIG_DIR/git" "$CONFIG_DIR"
ln -sf "$DOTS_CONFIG_DIR/tmux" "$CONFIG_DIR"  # tmux refuses to use XDG, this is for us to have tmux.conf
ln -sf "$DOTS_CONFIG_DIR/input" "$CONFIG_DIR"   # forwards config
ln -sfn "$DOTS_CONFIG_DIR/tmux" "$HOME/.tmux"  # tmux folder for tmux's sake

ln -sf "$DOTS_DIR/tmux.conf" "$HOME/.tmux.conf" # this one just forwards config
ln -sf "$DOTS_DIR/inputrc" "$HOME/.inputrc"   # forwards config

# binary stuff
ln -sfn "$DOTS_BIN_DIR/scripts" "$BIN_DIR/scripts"

# macOS specific but doesn't hurt
mkdir -p "$HOME/.hammerspoon/"
ln -sf "$DOTS_CONFIG_DIR/hammerspoon/init.lua" "$HOME/.hammerspoon/"
ln -sf "$DOTS_CONFIG_DIR/hammerspoon" "$CONFIG_DIR"

ln -sf "$DOTS_CONFIG_DIR/skhd/skhdrc" "$HOME/.skhdrc"
ln -sf "$DOTS_CONFIG_DIR/yabai/yabairc" "$HOME/.yabairc"
