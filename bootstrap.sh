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
  # Genuinely Ubuntu (for PPAs and ubuntu_version_ge gates). Prefer is_debian
  # for anything that just needs apt / Debian-family package names.
  [[ -f /etc/os-release ]] && grep -qi "ubuntu" /etc/os-release
}

function is_debian {
  # Debian family: Debian, Ubuntu, Raspberry Pi OS, Linux Mint, WSL Ubuntu, ...
  # i.e. anything that installs packages with apt.
  [[ -f /etc/debian_version ]] || command -v apt-get >/dev/null 2>&1
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
  elif is_debian; then
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
  if is_debian; then
    package="silversearcher-ag"
  fi
  _default_install_package "$package"
}

function _install_package_delta {
  _default_install_package "git-delta"
}

function _install_package_fd {
  if is_debian; then
    _default_install_package "fd-find"
    # Ubuntu names the binary fdfind to avoid conflict with fdclone
    ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"
  elif is_fedora || is_centos; then
    # Fedora/RHEL/CentOS package it as fd-find; binary is already `fd`
    _default_install_package "fd-find"
  else
    _default_install_package "fd"
  fi
}

function _install_package_tree-sitter {
  # Required by nvim-treesitter `main` branch to compile parsers on-host.
  # Note: Homebrew split the formula — bare `tree-sitter` is library-only;
  # the CLI lives at `tree-sitter-cli` (which still installs the binary as
  # `tree-sitter`).
  if is_mac; then
    _default_install_package "tree-sitter-cli"
  elif is_fedora; then
    _default_install_package "tree-sitter-cli"
  elif is_ubuntu; then
    if ubuntu_version_ge "24.04"; then
      _default_install_package "tree-sitter-cli"
    else
      _log_info "Installing ${color_blue}tree-sitter${color_reset} from GitHub releases (apt tree-sitter-cli landed in 24.04)"
      local ts_version=$(curl -s "https://api.github.com/repos/tree-sitter/tree-sitter/releases/latest" | jq -r '.tag_name | ltrimstr("v")')
      local arch
      case "$(uname -m)" in
        x86_64) arch="x64" ;;
        aarch64|arm64) arch="arm64" ;;
        *) _fail_error "Unsupported architecture for tree-sitter prebuilt: $(uname -m)" ;;
      esac
      local ts_url="https://github.com/tree-sitter/tree-sitter/releases/download/v${ts_version}/tree-sitter-linux-${arch}.gz"
      curl -Lo /tmp/tree-sitter.gz "$ts_url"
      gunzip -f /tmp/tree-sitter.gz
      sudo install /tmp/tree-sitter -D -t /usr/local/bin/
      rm -f /tmp/tree-sitter
    fi
  else
    _default_install_package "tree-sitter-cli"
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
  # gum is packaged widely now, so prefer native package managers and only fall
  # back to Charm's repos / a raw GitHub binary. Order: macOS brew -> native dnf
  # -> Debian-family apt (Charm repo) -> GitHub release binary.

  # macOS: Homebrew ships gum.
  if is_mac; then
    _default_install_package "gum"
    return
  fi

  # Fedora / RHEL / CentOS: gum is now in the official repos (Fedora + EPEL 10).
  # Try the native package first; only add Charm's yum repo if that misses.
  if command -v dnf5 >/dev/null 2>&1 || command -v dnf >/dev/null 2>&1; then
    local dnf_bin
    dnf_bin=$(command -v dnf5 || command -v dnf)
    if sudo "$dnf_bin" install gum -y; then
      return
    fi
    _log_warn "No native ${color_blue}gum${color_reset} package; adding ${color_blue}charm/gum${color_reset} yum repo"
    # NOTE: must be indented in this way to be valid config file
    echo '[charm]
name=Charm
baseurl=https://repo.charm.sh/yum/
enabled=1
gpgcheck=1
gpgkey=https://repo.charm.sh/yum/gpg.key' | sudo tee /etc/yum.repos.d/charm.repo
    sudo rpm --import https://repo.charm.sh/yum/gpg.key
    sudo "$dnf_bin" install gum -y && return
  fi

  # Debian family: Ubuntu, Debian, Raspberry Pi OS, WSL. Uses is_debian (NOT
  # is_ubuntu) so Debian/Pi are covered. Charm's apt repo serves arm64/armhf
  # too, so the Pi gets a real package.
  if is_debian; then
    _log_info "Adding ${color_blue}charm/gum${color_reset} apt repo"
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
    sudo apt-get update && sudo apt-get install gum -y && return
  fi

  # Universal fallback: raw release binary from GitHub into ~/.local/bin.
  _log_warn "No native package path for ${color_blue}gum${color_reset}; downloading a release binary"
  _install_gum_from_github
}

function _install_gum_from_github {
  local os arch tag ver url tmp gum_bin
  case "$(uname -s)" in
    Linux)   os="Linux" ;;
    Darwin)  os="Darwin" ;;
    FreeBSD) os="Freebsd" ;;
    *) _log_warn "Unsupported OS for gum binary: $(uname -s). Try: ${color_blue}go install github.com/charmbracelet/gum@latest"; return 1 ;;
  esac
  case "$(uname -m)" in
    x86_64|amd64)  arch="x86_64" ;;
    aarch64|arm64) arch="arm64" ;;
    armv7l|armv7)  arch="armv7" ;;
    armv6l|armv6)  arch="armv6" ;;
    i386|i686)     arch="i386" ;;
    *) _log_warn "Unsupported arch for gum binary: $(uname -m)"; return 1 ;;
  esac

  tag=$(curl -fsSL "https://api.github.com/repos/charmbracelet/gum/releases/latest" | jq -r '.tag_name') \
    || { _log_warn "Could not query gum releases (network?)"; return 1; }
  ver="${tag#v}"
  # Charm/goreleaser asset layout: gum_<ver>_<Os>_<Arch>.tar.gz
  url="https://github.com/charmbracelet/gum/releases/download/${tag}/gum_${ver}_${os}_${arch}.tar.gz"
  tmp=$(mktemp -d)
  _log_info "Downloading ${color_blue}gum ${ver}${color_reset} (${os}/${arch})"
  if ! curl -fsSL "$url" -o "$tmp/gum.tar.gz"; then
    _log_warn "Download failed: ${color_blue}$url"
    rm -rf "$tmp"; return 1
  fi
  tar -xzf "$tmp/gum.tar.gz" -C "$tmp" || { _log_warn "Failed to extract gum"; rm -rf "$tmp"; return 1; }
  gum_bin=$(find "$tmp" -name gum -type f | head -n1)
  mkdir -p "$HOME/.local/bin"
  install "$gum_bin" "$HOME/.local/bin/gum" || { _log_warn "Failed to install gum binary"; rm -rf "$tmp"; return 1; }
  rm -rf "$tmp"
  _log_info "Installed ${color_blue}gum${color_reset} to ${color_blue}$HOME/.local/bin/gum"
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
  # Ensure pip and venv modules are available (separate packages on Debian/Ubuntu)
  if is_debian; then
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

function _install_package_docker {
  # A prior `brew install docker` can leave the formula fully installed in
  # the Cellar but unlinked (e.g. a transient `brew link` conflict) --
  # `command -v docker` then fails forever and every bootstrap run retries
  # `brew install`, which is a no-op and never fixes the link. Relink
  # instead of reinstalling when that's the case.
  if is_mac && brew list --formula docker &>/dev/null; then
    _log_info "docker is installed but not linked - relinking"
    brew link --overwrite docker
  else
    _default_install_package "docker"
  fi
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

  # Fast path: if pynvim already imports, don't touch the network at all.
  # `pip install --upgrade` does a pypi round-trip on EVERY run; on a flaky or
  # proxied network the TLS handshake fails (WRONG_VERSION_NUMBER) and pip
  # retries with backoff for a minute+ per package before falling back to
  # "already satisfied". The local import check is ~0.3s and fully idempotent.
  if "$nvim_venv_path/bin/python3" -c "import pynvim" >/dev/null 2>&1; then
    _log_btw "Already installed: ${color_blue}pynvim${color_reset} in nvim venv. Skipping!"
    return 0
  fi

  # Install pynvim. Prefer uv (fast + cached); fall back to pip with fail-fast
  # timeouts so a dead network errors out instead of hanging on retries.
  _log_info "Installing ${color_blue}pynvim${color_reset} into neovim venv"
  if command -v uv >/dev/null 2>&1; then
    uv pip install --python "$nvim_venv_path/bin/python3" pynvim \
      || _log_warn "Failed to install pynvim via uv (network?). Run ${color_blue}nvim +checkhealth${color_reset} later."
  else
    "$nvim_venv_path/bin/pip3" install --timeout 15 --retries 1 pynvim \
      || _log_warn "Failed to install pynvim via pip (network?). Run ${color_blue}nvim +checkhealth${color_reset} later."
  fi
}

# TPM plugins live in dots/config/tmux/plugins (symlinked to ~/.tmux/plugins) but
# are gitignored, so a fresh checkout has no plugins at all. Worse: an EMPTY
# plugin dir left behind (e.g. by a half-finished clone or a dead submodule)
# makes TPM think the plugin is already installed, so `prefix + I` silently
# skips it forever -- which is exactly how tmux-resurrect ended up a no-op.
# Clone anything missing, and treat an empty dir as missing.
function setup_tmux_plugins {
  local plugins_dir="$DOTS_CONFIG_DIR/tmux/plugins"
  local -a plugins=(
    "tpm https://github.com/tmux-plugins/tpm"
    "tmux-sensible https://github.com/tmux-plugins/tmux-sensible"
    "tmux-themepack https://github.com/jimeh/tmux-themepack"
    "tmux-resurrect https://github.com/tmux-plugins/tmux-resurrect"
  )

  mkdir -p "$plugins_dir"

  local entry name url dest
  for entry in "${plugins[@]}"; do
    read -r name url <<< "$entry"
    dest="$plugins_dir/$name"

    # An existing but empty dir is a TPM landmine: remove it so we re-clone.
    if [[ -d "$dest" && -z "$(ls -A "$dest" 2>/dev/null)" ]]; then
      _log_warn "Empty tmux plugin dir ${color_blue}$name${color_reset}; re-cloning"
      rmdir "$dest"
    fi

    if [[ -d "$dest" ]]; then
      _log_btw "Already installed: ${color_blue}tmux plugin $name${color_reset}. Skipping!"
      continue
    fi

    _log_info "Cloning ${color_blue}tmux plugin $name${color_reset}"
    git clone --depth 1 "$url" "$dest" \
      || _log_warn "Failed to clone tmux plugin $name (network?). Run ${color_blue}prefix + I${color_reset} later."
  done

  # Pick up newly-installed plugins in any already-running server.
  if command -v tmux >/dev/null 2>&1 && tmux has-session 2>/dev/null; then
    tmux source-file "$HOME/.tmux.conf" >/dev/null 2>&1 \
      && _log_info "Reloaded tmux.conf in the running server"
  fi
}

function clone_dots {
  if [[ -d $HOME/dots/ ]]; then 
    _log_btw "Dots repo cloned. Skipping!"
    return
  fi
  _log_info "Cloning ${color_blue}alexpopov/dots${color_reset}"
  git clone --recursive https://github.com/alexpopov/dots.git $HOME/dots
}

# The --recursive above only helps a machine being set up for the first time.
# On every already-bootstrapped machine clone_dots returns early, so a submodule
# added later (tmux-continuum, say) would never arrive and tmux would silently
# load a config referencing a plugin that isn't on disk. Idempotent, so it just
# runs every time rather than trying to detect which case we're in.
function sync_submodules {
  if [[ ! -d $HOME/dots/.git ]]; then
    _log_warn "No dots git repo at $HOME/dots; skipping submodule sync."
    return
  fi
  _log_btw "Syncing git submodules (tmux plugins)."
  # `sync` first so a changed upstream URL in .gitmodules is picked up by
  # submodules that were already initialised against the old one.
  git -C "$HOME/dots" submodule sync --recursive --quiet \
    || _log_warn "git submodule sync failed; tmux plugins may be stale."
  git -C "$HOME/dots" submodule update --init --recursive \
    || _log_warn "git submodule update failed (network?). Run ${color_blue}git -C ~/dots submodule update --init --recursive${color_reset} later."
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
  ln -sf "$DOTS_CONFIG_DIR/claude-mcp" "$CONFIG_DIR" || _fail_error "Failed to symlink claude-mcp config"
  ln -sf "$DOTS_CONFIG_DIR/input" "$CONFIG_DIR" || _fail_error "Failed to symlink input config"
  if [[ "$USER" != "cay" ]]; then
    ln -sf "$DOTS_CONFIG_DIR/lazygit" "$CONFIG_DIR" || _fail_error "Failed to symlink lazygit config"
  fi
  ln -sf "$DOTS_CONFIG_DIR/karabiner" "$CONFIG_DIR" || _fail_error "Failed to symlink karabiner config"
  ln -sf "$DOTS_CONFIG_DIR/nvim" "$CONFIG_DIR" || _fail_error "Failed to symlink nvim config"
  if [[ "$USER" != "cay" ]]; then
    ln -sf "$DOTS_CONFIG_DIR/git" "$CONFIG_DIR" || _fail_error "Failed to symlink git config"
  fi
  # Personal media-stack units only; work computers already have a managed
  # ~/.config/systemd/user (a whole-dir symlink can't overwrite it anyway).
  if [[ "$USER" != "cay" ]] && ! is_work_computer; then
    ln -sf "$DOTS_CONFIG_DIR/systemd" "$CONFIG_DIR" || _fail_error "Failed to symlink systemd config"
  fi
  ln -sf "$DOTS_CONFIG_DIR/selinux" "$CONFIG_DIR" || _fail_error "Failed to symlink selinux config"
  ln -sf "$DOTS_CONFIG_DIR/ghostty" "$CONFIG_DIR" || _fail_error "Failed to symlink ghostty config"

  # Per-user ghostty overrides. The main config does `config-file = ?local.conf`,
  # so this file is optional. Written through the symlinked dir, so it lands in
  # dots/config/ghostty/local.conf — gitignored.
  if [[ "$USER" == "cay" ]]; then
    cat > "$CONFIG_DIR/ghostty/local.conf" <<'EOF' || _fail_error "Failed to write ghostty local.conf"
theme = TokyoNight Storm
EOF
  fi

  # kitty uses XDG: ~/.config/kitty/kitty.conf
  ln -sf "$DOTS_CONFIG_DIR/kitty" "$CONFIG_DIR" || _fail_error "Failed to symlink kitty config"

  # Per-user kitty overrides. The main config does `globinclude local.conf`,
  # so this file is optional. Written through the symlinked dir, so it lands
  # in dots/config/kitty/local.conf — gitignored.
  if [[ "$USER" == "cay" ]]; then
    cat > "$CONFIG_DIR/kitty/local.conf" <<'EOF' || _fail_error "Failed to write kitty local.conf"
# TokyoNight Storm-ish dark override
background       #24283b
foreground       #c0caf5
EOF
  fi


  # tmux refuses to use XDG, this is for us to have tmux.conf
  ln -sf "$DOTS_CONFIG_DIR/tmux" "$CONFIG_DIR" || _fail_error "Failed to symlink tmux config dir"
  ln -sfn "$DOTS_CONFIG_DIR/tmux" "$HOME/.tmux" || _fail_error "Failed to symlink ~/.tmux"
  ln -sf "$DOTS_DIR/tmux.conf" "$HOME/.tmux.conf" || _fail_error "Failed to symlink ~/.tmux.conf"

  # inputrc refuses to use XDG
  ln -sf "$DOTS_DIR/inputrc" "$HOME/.inputrc" || _fail_error "Failed to symlink ~/.inputrc"

  # ollama also refuses to use XDG
  mkdir -p "$HOME/.ollama"
  ln -sf "$DOTS_CONFIG_DIR/ollama/config.toml" "$HOME/.ollama/config.toml" || _fail_error "Failed to symlink ollama config"

  # pi also refuses to use XDG. settings.json: symlink the portable copy here
  # unless a machine-local REAL file already exists (a private overlay can
  # materialize one: this baseline + machine-specific keys). Never clobber it.
  mkdir -p "$HOME/.pi/agent/themes" "$HOME/.pi/agent/extensions"
  if [[ -L "$HOME/.pi/agent/settings.json" || ! -e "$HOME/.pi/agent/settings.json" ]]; then
    ln -sf "$DOTS_CONFIG_DIR/pi/settings.json" "$HOME/.pi/agent/settings.json" || _fail_error "Failed to symlink pi settings"
  fi
  ln -sf "$DOTS_CONFIG_DIR/pi/keybindings.json" "$HOME/.pi/agent/keybindings.json" || _fail_error "Failed to symlink pi keybindings"

  # pi themes and extensions - per-item symlinks so each dir can hold
  # dots-tracked items alongside machine-local or installed ones.
  if [[ -d "$DOTS_CONFIG_DIR/pi/themes" ]]; then
    for theme in "$DOTS_CONFIG_DIR/pi/themes"/*; do
      [[ -e "$theme" ]] || continue
      ln -sfn "$theme" "$HOME/.pi/agent/themes/$(basename "$theme")" \
        || _fail_error "Failed to symlink pi theme $(basename "$theme")"
    done
  fi
  if [[ -d "$DOTS_CONFIG_DIR/pi/extensions" ]]; then
    for ext in "$DOTS_CONFIG_DIR/pi/extensions"/*; do
      [[ -e "$ext" ]] || continue
      ln -sfn "$ext" "$HOME/.pi/agent/extensions/$(basename "$ext")" \
        || _fail_error "Failed to symlink pi extension $(basename "$ext")"
    done
  fi

  # Meta-only pi config (MCP servers, agent instructions) lives in fbsource,
  # not here -- this repo is public and that config names internal binaries,
  # corpora, and checkout paths. It links itself into ~/.pi/agent.
  local fbsource_pi_link="$HOME/fbsource/users/al/alexpopov/pi/link-pi-config.sh"
  if [[ -x "$fbsource_pi_link" ]]; then
    "$fbsource_pi_link" || _fail_error "Failed to link fbsource pi config"
  elif is_work_computer; then
    echo "NOTE: $fbsource_pi_link not found -- run it after fbsource is checked out"
  fi

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

  # Claude skills - symlink each skill directory individually
  mkdir -p "$HOME/.claude/skills"
  if [[ -d "$DOTS_CONFIG_DIR/claude/skills" ]]; then
    for skill_dir in "$DOTS_CONFIG_DIR/claude/skills"/*; do
      if [[ -d "$skill_dir" ]]; then
        local skill_name=$(basename "$skill_dir")
        ln -sfn "$skill_dir" "$HOME/.claude/skills/$skill_name" || _fail_error "Failed to symlink claude skill: $skill_name"
      fi
    done
  fi

  # Claude slash commands - symlink each command file individually
  mkdir -p "$HOME/.claude/commands"
  if [[ -d "$DOTS_CONFIG_DIR/claude/commands" ]]; then
    for command_file in "$DOTS_CONFIG_DIR/claude/commands"/*.md; do
      if [[ -f "$command_file" ]]; then
        local command_name=$(basename "$command_file")
        ln -sfn "$command_file" "$HOME/.claude/commands/$command_name" || _fail_error "Failed to symlink claude command: $command_name"
      fi
    done
  fi

  # Work-only Claude resources (e.g. qfil-flashing) live in fbsource, kept OUT
  # of this public repo. If that bootstrap exists on this machine, let it link
  # them into ~/.claude too. Absent on personal machines -> cleanly skipped.
  local fb_bootstrap="$HOME/fbsource/users/al/alexpopov/bootstrap.sh"
  if [[ -f "$fb_bootstrap" ]]; then
    echo "Running fbsource work bootstrap..."
    bash "$fb_bootstrap" || echo "warning: fbsource bootstrap failed (non-fatal)"
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
function configure_macos_defaults {
  is_mac || return 0

  # Stop Photos / Image Capture from auto-launching and grabbing a tethered
  # camera's single PTP session on connect — the main cause of EOS Utility
  # freezing or failing to detect the R5. Per-host (does not sync via iCloud),
  # so it must be set once on each Mac. See bin/scripts/eos-fix for recovery.
  if defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool YES; then
    _log_info "Disabled camera hot-plug auto-launch (Image Capture)"
  else
    _log_warn "Could not set Image Capture disableHotPlug"
  fi
}

# Upstream kitty's icon is... not great. DinkDonk/kitty-icon is a nicer
# drop-in. Two places matter on macOS:
#   1. ~/.config/kitty/kitty.app.icns -- kitty applies this itself at startup,
#      so it survives kitty upgrades (the app bundle gets replaced on update).
#   2. the app bundle itself -- so Finder/Dock/Spotlight show it even when
#      kitty isn't running.
# Set KITTY_ICON_VARIANT=light for the light version.
KITTY_ICON_REPO="https://github.com/DinkDonk/kitty-icon.git"

function install_kitty_icon {
  is_mac || return 0

  local variant="${KITTY_ICON_VARIANT:-dark}"
  local kitty_config_dir="$CONFIG_DIR/kitty"
  local dest="$kitty_config_dir/kitty.app.icns"

  if [[ ! -d "$kitty_config_dir" ]]; then
    _log_warn "No ${color_blue}$kitty_config_dir${color_reset}; skipping kitty icon"
    return 0
  fi

  local tmpdir
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/kitty-icon.XXXXXX")" || {
    _log_warn "Could not create temp dir for kitty icon"
    return 0
  }

  if ! git clone --depth 1 --quiet "$KITTY_ICON_REPO" "$tmpdir/repo" 2>/dev/null; then
    _log_warn "Could not clone ${color_blue}$KITTY_ICON_REPO${color_reset}; skipping kitty icon"
    rm -rf "$tmpdir"
    return 0
  fi

  local src="$tmpdir/repo/kitty-${variant}.icns"
  if [[ ! -f "$src" ]]; then
    _log_warn "No ${color_blue}kitty-${variant}.icns${color_reset} in kitty-icon repo; skipping"
    rm -rf "$tmpdir"
    return 0
  fi

  # Written through the symlinked dir, so it lands in
  # dots/config/kitty/kitty.app.icns -- gitignored.
  if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
    _log_btw "Already installed: ${color_blue}kitty icon (${variant})${color_reset}. Skipping!"
  else
    cp "$src" "$dest" || _log_warn "Failed to install kitty icon to $dest"
    _log_info "Installed ${color_blue}kitty icon (${variant})${color_reset} to $dest"
  fi

  rm -rf "$tmpdir"

  # Stamp the app bundle too, so the icon shows before kitty ever runs.
  local app="/Applications/kitty.app"
  local kitty_bin="$app/Contents/MacOS/kitty"
  if [[ -x "$kitty_bin" && -f "$dest" ]]; then
    if "$kitty_bin" +runpy 'from kitty.fast_data_types import cocoa_set_app_icon; import sys; cocoa_set_app_icon(*sys.argv[1:])' \
        "$dest" "$app" >/dev/null 2>&1; then
      _log_info "Applied kitty icon to ${color_blue}$app"
    else
      _log_warn "Could not stamp ${color_blue}$app${color_reset} with the custom icon"
    fi
  fi

  # The Dock caches app icons and won't notice until it's restarted.
  _log_warn "Dock caches icons. To see it now, run: ${color_blue}rm /var/folders/*/*/*/com.apple.dock.iconcache; killall Dock"
}

function setup_login_shell {
  # macOS ships bash 3.2.57 forever (GPLv3 + SIP), and /bin/bash can't be
  # replaced. Install a modern bash via Homebrew and make it the login shell
  # so terminals and tmux inherit bash 5.x. Fixes the kitty shell-integration
  # breakage (the bash-3.2 `set +o posix` handshake) among other things.
  # macOS only: Linux distros already ship bash 5.x as /bin/bash.
  is_mac || return 0

  local brew_bash="$(brew --prefix)/bin/bash"

  if [[ ! -x "$brew_bash" ]]; then
    _log_info "Installing modern ${color_blue}bash${color_reset} via Homebrew"
    brew install bash || _fail_error "Failed to ${color_blue}brew install bash"
  else
    _log_btw "Already installed: ${color_blue}Homebrew bash${color_reset}. Skipping!"
  fi

  # Register it as a legal login shell.
  if ! grep -qxF "$brew_bash" /etc/shells 2>/dev/null; then
    _log_info "Adding ${color_blue}$brew_bash${color_reset} to /etc/shells"
    echo "$brew_bash" | sudo tee -a /etc/shells >/dev/null || _fail_error "Could not write /etc/shells"
  else
    _log_btw "Already in /etc/shells: ${color_blue}$brew_bash${color_reset}. Skipping!"
  fi

  # Set it as the login shell via dscl (non-interactive; bootstrap already
  # holds sudo, so no separate chsh password prompt). Takes effect on next
  # login / new shell.
  local current
  current="$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}')"
  if [[ "$current" != "$brew_bash" ]]; then
    _log_info "Setting login shell to ${color_blue}$brew_bash"
    sudo dscl . -create "/Users/$USER" UserShell "$brew_bash" \
      || _log_warn "Could not set login shell; run ${color_blue}chsh -s $brew_bash${color_reset} manually"
  else
    _log_btw "Login shell already ${color_blue}$brew_bash${color_reset}. Skipping!"
  fi
}

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

# Acquire sudo ONCE, up front, in a clean terminal, then keep the timestamp
# warm in the background. Individual `sudo` calls later won't re-prompt.
# Why: a mid-run sudo prompt can land right after an interactive tool (e.g.
# `add-apt-repository`, a pager, or ssh-keygen) that left the tty with echo
# enabled -- which is exactly how the password ends up printed in cleartext.
# One clean prompt up front sidesteps that entirely. macOS uses brew (no sudo).
if ! is_mac && command -v sudo >/dev/null 2>&1; then
  _log_info "Requesting ${color_blue}sudo${color_reset} access up front (single prompt for the whole run)"
  if sudo -v; then
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true 2>/dev/null; sleep 50; done ) &
    _SUDO_KEEPALIVE_PID=$!
    trap '[[ -n "${_SUDO_KEEPALIVE_PID:-}" ]] && kill "$_SUDO_KEEPALIVE_PID" 2>/dev/null' EXIT
  else
    _log_warn "Could not acquire sudo up front; package installs may prompt individually."
  fi
fi

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
sync_submodules
export_fzf_bindings

# Packages that may rely on some manual intervention or the existence of dots dirs or something
# NOTE: write the binary name, not the package name
_LATE_PACKAGES_TO_INSTALL="python-utils gum cmake jq git-prev tree tree-sitter lazygit delta unzip zstd fd"

for package in $_LATE_PACKAGES_TO_INSTALL ; do 
  _install_package "$package"
done

for package in $(platform_specific_packages) ; do
  _install_package "$package"
done

create_links
ensure_shell_sources_dots

configure_macos_defaults  # no-op on non-macOS

install_kitty_icon       # macOS only: nicer kitty.app icon

setup_login_shell        # macOS only: modern Homebrew bash as login shell

setup_neovim_venv

setup_tmux_plugins       # clone TPM + plugins into dots/config/tmux/plugins

_log_info "Bootstrapping complete! 🎉 "

if is_wsl; then
  _log_warn "You're running in WSL! Run ${color_blue}~/dots/bootstrap_windows.sh${color_reset} to set up Windows apps and WSL extras."
fi
