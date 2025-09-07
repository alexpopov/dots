#!/bin/env bash

DOTS_DIR="$HOME/dots/"  # Set this absolute path
DOTS_CONFIG_DIR="$DOTS_DIR/config"
CONFIG_DIR="$HOME/.config"
DOTS_BIN_DIR="$DOTS_DIR/bin"
BIN_DIR="$HOME/.local/bin"

export color_red="\033[1;31m"
export color_green="\033[1;32m"
export color_yellow="\033[1;33m"
export color_blue="\033[1;34m"
export color_purple="\033[1;35m"
export color_cyan="\033[1;36m"
export color_grey="\033[0;37m"
export color_reset="\033[m"

function is_mac {
  [[ "$OSTYPE" == "darwin"* ]]
}

function is_fedora {
  [[ -f /etc/fedora-release ]]
}

function is_raspberry_pi {
  grep -q "Raspberry Pi" /proc/cpuinfo
}

function _fail_error {
  local error=1
  [[ -n $2 ]] && error="$2"
  echo -e "${color_red}ERR:  ${color_reset}$1${color_reset}"
  exit $error
}

function _log_info {
  echo -e "${color_green}INFO: ${color_reset}$1${color_reset}"
}

function _log_btw {
  echo -e "${color_grey}BTW:  ${color_reset}$1${color_reset}"
}

function _log_warn {
  echo -e "${color_yellow}WARN: ${color_reset}$1${color_reset}"
}

function _install_package {
  local package="$1"
  test -z "$package" && _fail_error "${color_blue}_install_package${color_blue} expects 1 argument" 

  # Check if already installed
  if command -v "$package" 2>&1 > /dev/null; then 
    _log_btw "Already installed: ${color_blue}$package${color_reset}. Skipping!"
    return 0
  fi

  # Check if we have custom install function
  if command -v "_install_package_${package}" 2>&1 > /dev/null; then 
    _log_info "Running custom installer: ${color_blue}$package${color_reset}."
    "_install_package_${package}" || _fail_error "Error running custom install function for ${color_blue}$package"
  else
    # Run default install
    _log_info "Running default installer: ${color_blue}$package${color_reset}."
    _default_install_package "$package" || _fail_error "Error installing ${color_blue}$package${color_reset} with default install function"
  fi
}

function _default_install_package {
  local package="$1"
  test -z "$package" && _fail_error "_default_install_package expects 1 argument"

  if is_mac; then
    brew install "$package"
  elif is_fedora; then
    sudo dnf5 install "$package" -y
  elif is_raspberry_pi; then
    sudo apt-get install "$package" -y
  else
    _fail_error "Unhandled OS in ${color_blue}_default_install_package"
  fi
}

function _install_package_et {
  local package="neovim"
  _default_install_package "$package"
  # Link commands
  _log_info "Linking ${color_blue}nvim${color_reset} as ${color_blue}~/.local/bin/vim${color_reset}"
  command -v nvim >/dev/null 2>&1 && ln -sf $(which nvim) ~/.local/bin/vim
}

function _install_package_et {
  local package="et"
  if is_mac; then
    package="MisterTea/et/et"
  elif is_raspberry_pi; then
    _log_info "Adding ${color_blue}apt${color_reset} repository for ${color_blue}et"
    sudo add-apt-repository ppa:jgmath2000/et
    sudo apt-get update
  fi
  _default_install_package "$package"
}

function _install_package_ag {
  # mac, fedora
  local package="the_silver_searcher"
  if is_raspberry_pi; then
    package="silversearcher-ag"
  fi
  _default_install_package "$package"
}

function _install_package_delta {
  _default_install_package "git-delta"
}

function _install_package_lazygit {
  local package="lazygit"
  is_fedora && sudo dnf copr enable dejan/lazygit
  _default_install_package "$package"
}

function _install_package_gum {
  local package="gum"
  if is_fedora; then
    _log_info "Adding ${color_blue}charm/gum${color_blue} repo"
    # NOTE: must be indented in this way to be valid config file
    echo '[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key' | sudo tee /etc/yum.repos.d/charm.repo
    sudo rpm --import https://repo.charm.sh/yum/gpg.key
  elif is_raspberry_pi; then 
    _log_info "Adding ${color_blue}charm/gum${color_blue} repo"
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
    sudo apt update
  fi
  _default_install_package "$package"
}

function _install_package_git-prev {
  local git_prev_path="$HOME/.local/share/git-prev-next"
  [[ -d $git_prev_path ]] && return 0
  git clone https://github.com/ridiculousfish/git-prev-next $git_prev_path
  _log_info "Linking ${color_blue}git-prev${color_reset} and ${color_blue}git-next${color_reset} into ${color_blue}~/.local/bin/"
  ln -sf $git_prev_path/git-next $HOME/.local/bin/ 
  ln -sf $git_prev_path/git-prev $HOME/.local/bin/ 
}

function clone_dots {
  if [[ -d $HOME/dots/ ]]; then 
    _log_btw "Dots repo cloned. Skipping!"
    return
  fi
  _log_info "Cloning ${color_blue}alexpopov/dots${color_reset}"
  git clone --recursive https://github.com/alexpopov/dots.git $HOME/dots
}

function export_fzf_bindings {
  local fzf_config_path="$HOME/.config/fzf/"
  local log_func=
  if [[ -f $fzf_config_path/fzf.bash ]]; then 
    log_func="_log_btw"
  else
    log_func="_log_info"
  fi
  mkdir -p "$fzf_config_path"
  fzf --bash > "$fzf_config_path"/fzf.bash
  "$log_func" "Exporting latest ${color_blue}fzf${color_reset} bash bindings:"
  "$log_func" "${color_blue}source $fzf_config_path${color_reset} for bindings"
}

function create_links {
  _log_btw "Creating links and necessary directories."
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
}

function create_basic_git_config {
  [[ -f $HOME/.gitconfig ]] && return 0
  _log_info "Gitconfig missing, creating a super basic one."
  echo '[user]
  name = Alex Popov
  email = hello@alexpopov.ca
[pull]
  rebase = true' | tee $HOME/.gitconfig
}

function ssh_config_support_github {
  local ssh_config="$HOME/.ssh/config" 
  # if does not exist: create file
  if [[ ! -f $ssh_config ]]; then 
    _log_info "Creating ssh config at ${color_blue}$ssh_config"
    touch "$ssh_config"
  fi
  # if contains github entry: return
  if grep -q "github.com" "$ssh_config"; then 
    _log_btw "Verified GitHub SSH config exists for @alexpopov"
    return
  fi
  _log_info "GitHub entry missing from SSH config."
  if [[ ! -f $HOME/.ssh/id_ed25519 ]]; then 
    _log_info "SSH key missing. Creating SSH key for GitHub. Please leave default name."
    ssh-keygen -t ed25519 -C "hello@alexpopov.ca" || _fail_error "Error creating SSH key, try RSA maybe? See ${color_blue}https://docs.github.com/en/authentication/connecting-to-github-with-ssh/generating-a-new-ssh-key-and-adding-it-to-the-ssh-agent"
  fi
  _log_info "Creating new SSH config entry to use ${color_blue}$HOME/.ssh/id_ed25519${color_reset} for GitHub"
  echo '
Host github.com
  AddKeysToAgent yes
  IdentityFile ~/.ssh/id_ed25519' | tee -a "$ssh_config"
  _log_info "Adding key to ${color_blue}ssh-agent${color_blue}"
  eval `ssh-agent -s`
  ssh-add $HOME/.ssh/id_ed25519
  _log_warn "you need to ${color_blue}cat $HOME/.ssh/id_ed25519.pub${color_reset} and add the result to your SSH keys in github"
  _log_warn "You may need to manually add SSH origin to the local dots git repo. Run: "
  _log_warn "${color_blue}git remote set-url origin git@github.com:alexpopov/dots.git"
}

#    ___           _          ____        _      __ 
#   / _ )___ ___ _(_)__      / __/_______(_)__  / /_
#  / _  / -_) _ `/ / _ \    _\ \/ __/ __/ / _ \/ __/
# /____/\__/\_, /_/_//_/   /___/\__/_/ /_/ .__/\__/ 
#          /___/                        /_/         

mkdir -p $HOME/{.local/{bin,share},.config/}

# The most important packages to install for setup
# NOTE: write the binary name, not the package name
_BOOTSTRAP_PACKAGES_TO_INSTALL="vim nvim git et tmux fzf ag python3"

for PACKAGE in $_BOOTSTRAP_PACKAGES_TO_INSTALL ; do 
  _install_package "$PACKAGE"
done

# New personal systems have nothing set in gitconfig
create_basic_git_config
ssh_config_support_github

# This requires git, which isn't installed on everything by default
clone_dots
export_fzf_bindings

# Packages that may rely on some manual intervention or the existence of dots dirs or something
# NOTE: write the binary name, not the package name
_LATE_PACKAGES_TO_INSTALL="gum cmake jq git-prev tree lazygit delta"

for PACKAGE in $_LATE_PACKAGES_TO_INSTALL ; do 
  _install_package "$PACKAGE"
done

create_links
