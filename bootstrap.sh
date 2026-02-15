#!/usr/bin/env bash

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

function is_centos {
  [[ -f /etc/centos-release ]]
}

function is_ubuntu {
  [[ -f /etc/ubuntu-release ]] || [[ -f /etc/os-release ]] && grep -qi "ubuntu" /etc/os-release
}

function ubuntu_version_ge {
  # Check if current Ubuntu version is >= the specified version (e.g., "25.10")
  local required_version="$1"
  local current_version=$(grep VERSION_ID /etc/os-release | cut -d= -f2 | tr -d '"')
  [[ "$(printf '%s\n' "$required_version" "$current_version" | sort -V | head -n1)" == "$required_version" ]]
}

function is_wsl {
  grep -qi microsoft /proc/version 2>/dev/null
}

function is_devserver {
  [[ -f /etc/fbwhoami ]] && grep -q "DEVICE_HOSTNAME_SCHEME" /etc/fbwhoami
}

function is_work_computer {
  if is_mac; then
    [[ -d "/usr/facebook" ]] || [[ -d "/opt/chef" ]]
  else
    # For devservers and other Linux work machines
    is_devserver
  fi
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
  elif is_ubuntu; then
    sudo apt-get install "$package" -y
  elif is_centos; then
    sudo dnf install "$package" -y
  else
    _fail_error "Unhandled OS in ${color_blue}_default_install_package"
  fi
}

function _install_package_nvim {
  if is_ubuntu; then
    # Ubuntu's apt neovim is ancient, install from GitHub
    _log_info "Installing ${color_blue}neovim${color_reset} from GitHub releases (apt version is too old)"
    local nvim_version=$(curl -s "https://api.github.com/repos/neovim/neovim/releases/latest" | jq -r '.tag_name | ltrimstr("v")')
    local nvim_url="https://github.com/neovim/neovim/releases/download/v${nvim_version}/nvim-linux-x86_64.tar.gz"
    curl -Lo /tmp/nvim.tar.gz "$nvim_url"
    tar xf /tmp/nvim.tar.gz -C /tmp
    sudo rm -rf /usr/local/lib/nvim
    sudo mv /tmp/nvim-linux-x86_64/lib/nvim /usr/local/lib/nvim
    sudo mv /tmp/nvim-linux-x86_64/share/nvim /usr/local/share/nvim
    sudo install /tmp/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
    rm -rf /tmp/nvim.tar.gz /tmp/nvim-linux-x86_64
  else
    _default_install_package "neovim"
  fi
  # Link commands
  _log_info "Linking ${color_blue}nvim${color_reset} as ${color_blue}~/.local/bin/vim${color_reset}"
  command -v nvim >/dev/null 2>&1 && ln -sf $(which nvim) ~/.local/bin/vim
}

function _install_package_fzf {
  if is_ubuntu; then
    # Ubuntu's apt fzf is ancient and missing --bash, install from GitHub
    _log_info "Installing ${color_blue}fzf${color_reset} from GitHub releases (apt version is too old)"
    local fzf_version=$(curl -s "https://api.github.com/repos/junegunn/fzf/releases/latest" | jq -r '.tag_name | ltrimstr("v")')
    local fzf_url="https://github.com/junegunn/fzf/releases/download/v${fzf_version}/fzf-${fzf_version}-linux_amd64.tar.gz"
    curl -Lo /tmp/fzf.tar.gz "$fzf_url"
    tar xf /tmp/fzf.tar.gz -C /tmp fzf
    sudo install /tmp/fzf -D -t /usr/local/bin/
    rm /tmp/fzf /tmp/fzf.tar.gz
  else
    _default_install_package "fzf"
  fi
}

function _install_package_et {
  local package="et"
  if is_mac; then
    package="MisterTea/et/et"
  elif is_ubuntu; then
    _log_info "Adding ${color_blue}apt${color_reset} repository for ${color_blue}et"
    sudo add-apt-repository ppa:jgmath2000/et
    sudo apt-get update
  fi
  _default_install_package "$package"
  if is_fedora || is_ubuntu ; then
    _log_info "Enabling et server"
    sudo systemctl enable --now et.service
  fi
}

function _install_package_ag {
  # mac, fedora
  local package="the_silver_searcher"
  if is_ubuntu; then
    package="silversearcher-ag"
  fi
  _default_install_package "$package"
}

function _install_package_delta {
  _default_install_package "git-delta"
}

function _install_package_fd {
  if is_ubuntu; then
    _default_install_package "fd-find"
    # Ubuntu names the binary fdfind to avoid conflict with fdclone
    ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"
  else
    _default_install_package "fd"
  fi
}

function _install_package_lazygit {
  local package="lazygit"

  if is_fedora; then
    sudo dnf copr enable dejan/lazygit
    _default_install_package "$package"
  elif is_ubuntu; then
    if ubuntu_version_ge "25.10"; then
      _default_install_package "$package"
    else
      _log_info "Installing ${color_blue}lazygit${color_reset} from GitHub releases"
      local lazygit_version=$(curl -s "https://api.github.com/repos/jesseduffield/lazygit/releases/latest" | jq -r '.tag_name | ltrimstr("v")')
      local lazygit_url="https://github.com/jesseduffield/lazygit/releases/download/v${lazygit_version}/lazygit_${lazygit_version}_Linux_x86_64.tar.gz"
      curl -Lo /tmp/lazygit.tar.gz "$lazygit_url"
      tar xf /tmp/lazygit.tar.gz -C /tmp lazygit
      sudo install /tmp/lazygit -D -t /usr/local/bin/
      rm /tmp/lazygit /tmp/lazygit.tar.gz
    fi
  elif is_centos; then
    _log_warn "Lazygit requires manual installation on CentOS/devservers"
    _log_info "Follow these steps:"
    _log_info "1. Visit ${color_blue}https://github.com/jesseduffield/lazygit/releases"
    _log_info "2. Find the ${color_blue}linux_x86_64.tar.gz${color_reset} asset and copy its link address"
    _log_info "3. Run the following commands:"
    _log_info "   ${color_blue}pushd ~/.local/share"
    _log_info "   ${color_blue}wget <paste-the-link-here>"
    _log_info "   ${color_blue}tar -xzf lazygit_*_linux_x86_64.tar.gz"
    _log_info "   ${color_blue}ln -sf ~/.local/share/lazygit ~/.local/bin/lazygit"
    _log_info "   ${color_blue}popd"
    echo ""
    read -p "Press Enter to continue after completing the installation..."
  else
    _default_install_package "$package"
  fi
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
  elif is_ubuntu; then
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
  if [[ -d $git_prev_path ]]; then
    _log_btw "Already cloned: ${color_blue}git-prev-next${color_reset}. Skipping!"
    return 0
  fi
  git clone https://github.com/ridiculousfish/git-prev-next $git_prev_path
  _log_info "Linking ${color_blue}git-prev${color_reset} and ${color_blue}git-next${color_reset} into ${color_blue}~/.local/bin/"
  ln -sf $git_prev_path/git-next $HOME/.local/bin/ 
  ln -sf $git_prev_path/git-prev $HOME/.local/bin/ 
}

function _install_package_python-utils {
  # Ensure pip and venv modules are available (separate packages on Ubuntu)
  if is_ubuntu; then
    if ! python3 -m pip --version >/dev/null 2>&1; then
      _log_info "Installing ${color_blue}python3-pip"
      sudo apt-get install python3-pip -y
    else
      _log_btw "Already installed: ${color_blue}python3-pip${color_reset}. Skipping!"
    fi
    if ! python3 -c "import ensurepip" 2>/dev/null; then
      _log_info "Installing ${color_blue}python3-venv"
      sudo apt-get install python3-venv -y
    else
      _log_btw "Already installed: ${color_blue}python3-venv${color_reset}. Skipping!"
    fi
  fi
}

function _install_package_avahi-daemon {
  _default_install_package "avahi"
  _log_info "Enabling avahi-daemon"
  sudo systemctl enable --now avahi-daemon
}

function _install_package_uv {
  _log_info "Installing ${color_blue}uv${color_reset} via official installer"
  curl -LsSf https://astral.sh/uv/install.sh | sh
}

function setup_neovim_venv {
  local nvim_venv_path="$HOME/.local/virtualenvs/nvim"
  local python_bin="python3"

  # Prefer Homebrew Python on macOS (has modern deployment target)
  if is_mac; then
    if [[ -x "/opt/homebrew/bin/python3" ]]; then
      python_bin="/opt/homebrew/bin/python3"
    elif [[ -x "/usr/local/bin/python3" ]]; then
      python_bin="/usr/local/bin/python3"
    fi
  fi

  # Create venv if it doesn't exist
  if [[ ! -d "$nvim_venv_path" ]]; then
    _log_info "Creating neovim Python virtual environment using ${color_blue}$python_bin"
    mkdir -p "$HOME/.local/virtualenvs"
    "$python_bin" -m venv "$nvim_venv_path"
  else
    _log_btw "Already created: ${color_blue}nvim virtual env${color_reset}. Skipping!"
  fi

  # Upgrade pip and install/upgrade pynvim and neovim-remote
  _log_btw "Upgrading ${color_blue}pip${color_reset}, ${color_blue}pynvim${color_reset}, and ${color_blue}neovim-remote${color_reset} in neovim venv"
  "$nvim_venv_path/bin/pip3" install --upgrade pip
  "$nvim_venv_path/bin/pip3" install --upgrade --index-url https://pypi.org/simple pynvim neovim-remote

  # Symlink nvr to ~/.local/bin as nvr-classic
  ln -sf "$nvim_venv_path/bin/nvr" "$HOME/.local/bin/nvr-classic"
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
  fzf --bash > "$fzf_config_path"/fzf.bash || _fail_error "fzf --bash failed; is fzf too old?"
  "$log_func" "Exporting latest ${color_blue}fzf${color_reset} bash bindings:"
  "$log_func" "${color_blue}source $fzf_config_path${color_reset} for bindings"
}

function create_links {
  _log_btw "Creating links and necessary directories."
  # Make all necessary directories
  mkdir -p "$CONFIG_DIR" "$DOTS_CONFIG_DIR" "$BIN_DIR" 

  ln -sf "$DOTS_CONFIG_DIR/bash" "$CONFIG_DIR" || _fail_error "Failed to symlink bash config"
  ln -sf "$DOTS_CONFIG_DIR/input" "$CONFIG_DIR" || _fail_error "Failed to symlink input config"
  ln -sf "$DOTS_CONFIG_DIR/lazygit" "$CONFIG_DIR" || _fail_error "Failed to symlink lazygit config"
  ln -sf "$DOTS_CONFIG_DIR/karabiner" "$CONFIG_DIR" || _fail_error "Failed to symlink karabiner config"
  ln -sf "$DOTS_CONFIG_DIR/nvim" "$CONFIG_DIR" || _fail_error "Failed to symlink nvim config"
  ln -sf "$DOTS_CONFIG_DIR/opencode" "$CONFIG_DIR" || _fail_error "Failed to symlink opencode config"
  ln -sf "$DOTS_CONFIG_DIR/git" "$CONFIG_DIR" || _fail_error "Failed to symlink git config"
  ln -sf "$DOTS_CONFIG_DIR/systemd" "$CONFIG_DIR" || _fail_error "Failed to symlink systemd config"
  ln -sf "$DOTS_CONFIG_DIR/selinux" "$CONFIG_DIR" || _fail_error "Failed to symlink selinux config"

  # tmux refuses to use XDG, this is for us to have tmux.conf
  ln -sf "$DOTS_CONFIG_DIR/tmux" "$CONFIG_DIR" || _fail_error "Failed to symlink tmux config dir"
  ln -sfn "$DOTS_CONFIG_DIR/tmux" "$HOME/.tmux" || _fail_error "Failed to symlink ~/.tmux"
  ln -sf "$DOTS_DIR/tmux.conf" "$HOME/.tmux.conf" || _fail_error "Failed to symlink ~/.tmux.conf"

  # inputrc refuses to use XDG
  ln -sf "$DOTS_DIR/inputrc" "$HOME/.inputrc" || _fail_error "Failed to symlink ~/.inputrc"

  # ollama also refuses to use XDG
  mkdir -p "$HOME/.ollama"
  ln -sf "$DOTS_CONFIG_DIR/ollama/config.toml" "$HOME/.ollama/config.toml" || _fail_error "Failed to symlink ollama config"

  # binary stuff
  ln -sfn "$DOTS_BIN_DIR/scripts" "$BIN_DIR/scripts" || _fail_error "Failed to symlink scripts"

  # macOS specific but doesn't hurt
  mkdir -p "$HOME/.hammerspoon/"
  ln -sf "$DOTS_CONFIG_DIR/hammerspoon/init.lua" "$HOME/.hammerspoon/" || _fail_error "Failed to symlink hammerspoon init.lua"
  ln -sf "$DOTS_CONFIG_DIR/hammerspoon" "$CONFIG_DIR" || _fail_error "Failed to symlink hammerspoon config"

  ln -sf "$DOTS_CONFIG_DIR/skhd/skhdrc" "$HOME/.skhdrc" || _fail_error "Failed to symlink skhdrc"
  ln -sf "$DOTS_CONFIG_DIR/yabai/yabairc" "$HOME/.yabairc" || _fail_error "Failed to symlink yabairc"

  if is_mac; then
    mkdir -p "$HOME/.docker"
    ln -sf "$DOTS_CONFIG_DIR/docker/config_macos.json" "$HOME/.docker/config.json" || _fail_error "Failed to symlink docker config"
  fi
}

function ensure_shell_sources_dots {
  local source_line='. "$HOME/.config/bash/bash_profile.sh"'

  # Check if either file already sources our config
  for rc in "$HOME/.bashrc" "$HOME/.bash_profile"; do
    if [[ -f "$rc" ]] && grep -qF '.config/bash/bash_profile.sh' "$rc"; then
      _log_btw "Already sourcing dots config from ${color_blue}$rc${color_reset}. Skipping!"
      return 0
    fi
  done

  # Append to ~/.bashrc
  _log_info "Adding dots source line to ${color_blue}~/.bashrc"
  echo "" >> "$HOME/.bashrc"
  echo "# Added by dots bootstrap" >> "$HOME/.bashrc"
  echo "$source_line" >> "$HOME/.bashrc"

  # Ensure ~/.bash_profile forwards to ~/.bashrc (for login shells)
  if [[ ! -f "$HOME/.bash_profile" ]]; then
    _log_info "Creating ${color_blue}~/.bash_profile${color_reset} to forward to ${color_blue}~/.bashrc"
    echo '# Forward to ~/.bashrc so everything lives in one place' > "$HOME/.bash_profile"
    echo '[ -f ~/.bashrc ] && . ~/.bashrc' >> "$HOME/.bash_profile"
  fi
}

function create_basic_git_config {
  if [[ -f $HOME/.gitconfig ]]; then
    _log_btw "Already exists: ${color_blue}~/.gitconfig${color_reset}. Skipping!"
    return 0
  fi
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

# print packages as words
function platform_specific_packages {
  local packages=()
  if is_mac; then
    if ! is_work_computer; then
      packages+=("docker" "docker-buildx")
    fi
  elif is_fedora; then
    if ! is_work_computer; then
      # for bonjour-style local mDNS resolution
      packages+="avahi-daemon"

      # docker-compose but better
      packages+=("podman" "podman-compose")

      # selinux tools
      packages+=("setools-console")

      packages+=("unrar")
    fi
  fi
  echo "${packages[@]}"
}

TODOs=(
  "implement Mac app downloads with ${color_blue}brew --cask, e.g. Alfred"
  "Other Mac apps: Maccy, Divvy, Rocket, Karabiner, Hammerspoon, Captin"
  "Mac-specific utilities: skhd, yabai"
  "File with platform-specific TODOs and only print per platform"
  "Use tuned on Fedora to use less power?"
)
for todo in "${TODOs[@]}"; do 
  _log_warn "${color_green}TODO${color_reset}: $todo${color_reset}"
done
#    ___           _          ____        _      __ 
#   / _ )___ ___ _(_)__      / __/_______(_)__  / /_
#  / _  / -_) _ `/ / _ \    _\ \/ __/ __/ / _ \/ __/
# /____/\__/\_, /_/_//_/   /___/\__/_/ /_/ .__/\__/ 
#          /___/                        /_/         
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    _log_info "Thanks for sourcing! The rest of the script will not be executed."
    _log_info "If you'd like to execute the script, call it without ${color_blue}source"
    return
fi

mkdir -p $HOME/{.local/{bin,share},.config/}

# The most important packages to install for setup
# NOTE: write the binary name, not the package name
_BOOTSTRAP_PACKAGES_TO_INSTALL="vim jq nvim git et tmux fzf ag python3 uv"

for package in $_BOOTSTRAP_PACKAGES_TO_INSTALL ; do 
  _install_package "$package"
done

# New personal systems have nothing set in gitconfig
create_basic_git_config
ssh_config_support_github

# This requires git, which isn't installed on everything by default
clone_dots
export_fzf_bindings

# Packages that may rely on some manual intervention or the existence of dots dirs or something
# NOTE: write the binary name, not the package name
_LATE_PACKAGES_TO_INSTALL="python-utils gum cmake jq git-prev tree lazygit delta unzip zstd fd"

for package in $_LATE_PACKAGES_TO_INSTALL ; do 
  _install_package "$package"
done

for package in $(platform_specific_packages) ; do
  _install_package "$package"
done

create_links
ensure_shell_sources_dots

setup_neovim_venv

_log_info "Bootstrapping complete! 🎉 "

if is_wsl; then
  _log_warn "You're running in WSL! Run ${color_blue}~/dots/bootstrap_windows.sh${color_reset} to set up Windows apps and WSL extras."
fi
