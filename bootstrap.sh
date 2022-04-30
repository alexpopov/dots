DOTS_DIR="$HOME/dots/"  # Set this absolute path
DOTS_CONFIG_DIR="$DOTS_DIR/config"
CONFIG_DIR="$HOME/.config"
mkdir -p "$CONFIG_DIR"
ln -s "$DOTS_CONFIG_DIR/bash" "$CONFIG_DIR"
ln -s "$DOTS_CONFIG_DIR/input" "$CONFIG_DIR"
ln -s "$DOTS_CONFIG_DIR/lazygit" "$CONFIG_DIR"
ln -s "$DOTS_CONFIG_DIR/nvim" "$CONFIG_DIR"
ln -s "$DOTS_CONFIG_DIR/tmux" "$CONFIG_DIR"  # tmux refuses to use XDG, this is for us to have tmux.conf
ln -s "$DOTS_CONFIG_DIR/input" "$CONFIG_DIR"   # forwards config
ln -s "$DOTS_CONFIG_DIR/tmux" "$HOME/.tmux"  # tmux folder for tmux's sake
ln -s "$DOTS_DIR/tmux.conf" "$HOME/.tmux.conf" # this one just forwards config
ln -s "$DOTS_DIR/inputrc" "$HOME/.inputrc"   # forwards config
