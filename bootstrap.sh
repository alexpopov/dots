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
    tmux source-file "$HOME/.config/tmux/tmux.conf" >/dev/null 2>&1 \
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

# Cache fzf's bash bindings at ONE path, ~/.config/fzf/fzf.bash, which is the
# first thing _dots_source_fzf looks for. fzf has moved these around: `fzf
# --bash` only exists from 0.48, before that the bindings shipped as separate
# key-bindings.bash / completion.bash files. Handle both so an old box does not
# silently end up with no bindings at all.
function export_fzf_bindings {
  local fzf_config_path="$HOME/.config/fzf"
  local dest="$fzf_config_path/fzf.bash"
  local log_func=
  if [[ -f "$dest" ]]; then
    log_func="_log_btw"
  else
    log_func="_log_info"
  fi

  if ! command -v fzf >/dev/null 2>&1; then
    _log_warn "No ${color_blue}fzf${color_reset} on PATH; skipping its bash bindings"
    return 0
  fi

  mkdir -p "$fzf_config_path"

  if fzf --bash >/dev/null 2>&1; then
    fzf --bash > "$dest" || { _fail_error "fzf --bash failed"; return 1; }
  else
    # fzf < 0.48: stitch the shipped files together into the same cache file.
    local d found=
    for d in \
        "$(brew --prefix 2>/dev/null)/opt/fzf/shell" \
        /usr/local/opt/fzf/shell \
        /usr/share/fzf/shell \
        /usr/share/fzf \
        /usr/share/doc/fzf/examples
    do
      if [[ -r "$d/key-bindings.bash" ]]; then
        cat "$d/key-bindings.bash" > "$dest"
        [[ -r "$d/completion.bash" ]] && cat "$d/completion.bash" >> "$dest"
        found=1
        break
      fi
    done
    if [[ -z "$found" ]]; then
      _log_warn "fzf is too old for ${color_blue}--bash${color_reset} and its shell/ files were not found; no bindings written"
      return 0
    fi
  fi

  "$log_func" "Exported ${color_blue}fzf${color_reset} bash bindings to ${color_blue}$dest"
}

# _sync_links <src> <dst>: make <dst> reflect <src> for items owned by <src>.
# Links every item of <src> into <dst>, then prunes symlinks in <dst> that
# point into <src> but whose target is gone (deleted/renamed upstream).
# Foreign entries in <dst> (real files, links to other roots) are untouched,
# so several linkers can share one dir as long as their source roots differ.
# NOTE: dotfiles/ondemand_support.sh carries a deliberate twin of this prune
# for the OD bundle. Do NOT factor them into a shared helper: the materialize
# block must run on boxes with no ~/dots, so it cannot source anything here.
# Path rule (triple-found 2026-10-29: double-slash, trailing-slash,
# unexpanded-tilde): NEVER compare or stat a path without normalizing it
# first — expanduser, then squeeze repeated slashes, then strip one trailing.
function _sync_links {
  local src="$1" dst="$2" item link target src_n target_n
  [[ -d "$src" ]] || return 0
  mkdir -p "$dst"
  for item in "$src"/*; do
    [[ -e "$item" ]] || continue
    ln -sfn "$item" "$dst/$(basename "$item")" \
      || _fail_error "Failed to symlink $(basename "$item")"
  done
  # Normalize slashes before prefix-matching: links minted when DOTS_DIR had
  # a trailing slash point at ".../dots//config/...", which must still count
  # as owned by this source. Raw string compare would silently skip the prune.
  src_n=$(printf %s "$src" | tr -s '/'); src_n=${src_n%/}
  for link in "$dst"/*; do
    [[ -L "$link" ]] || continue
    target_n=$(readlink "$link" | tr -s '/')
    case "$target_n" in
      "$src_n"/*) [[ -e "$link" ]] || rm -f "$link" ;;
    esac
  done
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

  # ALL pi config now lives in ~/dotfiles/pi, not here -- settings baseline
  # included (~/dotfiles/pi/base). dots used to own the portable half and the
  # overlay merged on top, which meant two homes, a two-layer merge, and a
  # packed od/pi bundle existing purely because OnDemands have no ~/dots.
  # One home, one installer. link-pi-config.sh does the whole job and works
  # identically on a devserver, an OnDemand and a Mac.
  #
  # Macs: ~/dotfiles is not writable from inside pi's seatbelt sandbox and has
  # no dotsync daemon, so refreshing it is a human step, run outside pi:
  #   dotsync2 --run-on-mac --dir "$HOME" partial-pull --paths dotfiles/pi
  local meta_pi_link="$HOME/dotfiles/pi/link-pi-config.sh"
  if [[ -x "$meta_pi_link" ]]; then
    "$meta_pi_link" || _fail_error "Failed to link pi config"
  elif is_work_computer; then
    echo "NOTE: $meta_pi_link not found -- pi will have NO config until it is"
    echo "      pulled: dotsync2 --dir \"\$HOME\" partial-pull --paths dotfiles/pi"
  fi

  # binary stuff
  ln -sfn "$DOTS_BIN_DIR/scripts" "$BIN_DIR/scripts" || _fail_error "Failed to symlink scripts"

  # Git hooks for this repo (bin/hooks/post-commit keeps the OD bundle in step
  # with config changes, and does nothing on machines with no ~/dotfiles).
  # Idempotent: core.hooksPath is local config, so re-running just rewrites it.
  git -C "$DOTS_DIR" config core.hooksPath "$DOTS_BIN_DIR/hooks" \
    || _log_warn "Could not set core.hooksPath (non-fatal)"

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

  # Claude skills and slash commands - per-item symlinks, so each dir can hold
  # dots-tracked items alongside locally-installed ones (this box has 12 from
  # dots next to 32 installed from the marketplace, which must not be touched).
  # _sync_links also PRUNES its own stale links: skills renamed or removed in
  # dots used to leave danglers here, and Claude reports those as broken skills.
  _sync_links "$DOTS_CONFIG_DIR/claude/skills" "$HOME/.claude/skills"
  _sync_links "$DOTS_CONFIG_DIR/claude/commands" "$HOME/.claude/commands"
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

# Chrome is a special case and is deliberately absent from the Brewfile.
# On a Meta-provisioned Mac it arrives via MDM / Managed Software Center and is
# patched from there; installing the cask on top means brew tries to adopt the
# managed bundle (`chgrp -hR admin`, which needs sudo) and then owns updates
# for an app the fleet expects to control. So: only on a personal Mac, and only
# when it is genuinely missing.
function _install_google_chrome {
  is_mac || return 0
  command -v brew >/dev/null 2>&1 || return 0

  if [[ -d "/Applications/Google Chrome.app" ]]; then
    _log_btw "Already installed: ${color_blue}Google Chrome${color_reset} (leaving it alone). Skipping!"
    return 0
  fi
  if is_work_computer; then
    _log_warn "No Chrome on this work Mac: install it from ${color_blue}Managed Software Center${color_reset}, not brew"
    return 0
  fi

  _log_info "Installing ${color_blue}Google Chrome"
  brew install --cask google-chrome || _log_warn "Could not install Google Chrome"
}

# Install the GUI apps listed in the Brewfile. The formulae in there mostly
# duplicate what _install_package already did (harmless -- brew is idempotent);
# the casks are the point. A freshly provisioned Mac has none of
# Alfred/Karabiner/kitty/Ghostty, and every macOS tweak below then has nothing
# to act on.
function install_brew_bundle {
  is_mac || return 0
  command -v brew >/dev/null 2>&1 || { _log_warn "No ${color_blue}brew${color_reset}; skipping Brewfile"; return 0; }

  local brewfile="$DOTS_DIR/Brewfile"
  [[ -f "$brewfile" ]] || { _log_warn "No ${color_blue}$brewfile${color_reset}; skipping"; return 0; }

  if brew bundle check --file="$brewfile" >/dev/null 2>&1; then
    _log_btw "Already installed: ${color_blue}everything in the Brewfile${color_reset}. Skipping!"
    return 0
  fi

  _log_info "Installing apps from ${color_blue}$brewfile${color_reset} (casks may prompt for sudo)"
  # --no-upgrade: install only what is missing. Re-running bootstrap should not
  # silently drag every app to a new major version.
  # --adopt: a provisioned Mac already has some of these (Chrome, WezTerm).
  # Without it brew refuses with "It seems the existing App is different from
  # the one being installed" and the whole bundle reports failure. Scoped to
  # this one command -- HOMEBREW_CASK_OPTS is appended to *every* cask
  # subcommand, and `brew list --cask --adopt` is an error.
  HOMEBREW_CASK_OPTS="--adopt" brew bundle install --file="$brewfile" --no-upgrade \
    || _log_warn "Some Brewfile entries failed; see ${color_blue}brew bundle check --file=$brewfile --verbose"

  _install_google_chrome

  # Casks whose payload is an installer .pkg need a real sudo prompt, so they
  # can never be installed from a script running over a non-interactive ssh.
  local pkg_casks="karabiner-elements choosy"
  local still_missing="" c
  for c in $pkg_casks; do
    brew list --cask "$c" >/dev/null 2>&1 || still_missing="$still_missing $c"
  done
  if [[ -n "$still_missing" ]]; then
    _log_warn "Needs a real terminal (pkg installer + sudo):${color_blue}$still_missing"
    _log_warn "Run it yourself:${color_blue} brew install --cask$still_missing"
  fi
}

#    __  ___            ____  ____    __      ____         ____
#   /  |/  /__ _ _____ / __ \/ __/___/ /__ __/ _/__ ___ __/ / /____
#  / /|_/ / _ `/ __/ _ \ /_/ /\ \/___/ / // / _/ _ `/ // / / __(_-<
# /_/  /_/\_,_/\__/\___/____/___/  /_/\_,_/_/ \_,_/\_,_/_/\__/___/
#
# Every value below was read off the old MacBook with `defaults read` rather
# than invented. Keep it that way: change the setting in System Settings, read
# the new value, paste it here.
#
# NOT scriptable, still manual after this runs:
#   - Karabiner-Elements needs Input Monitoring granted (System Settings >
#     Privacy & Security). Its config -- caps_lock -> escape, escape -> f20 --
#     is in dots/config/karabiner and is already symlinked by create_links, so
#     granting the permission is the only step.
#   - yabai's scripting addition needs SIP partially disabled.
#   - Alfred's own cmd-space hotkey is set inside Alfred (its prefs live in
#     ~/Library/Application Support/Alfred). This script only frees the key by
#     switching Spotlight's shortcut off.
function _defw {
  # _defw <domain> <key> <type> <value...>   -- use `-g` for NSGlobalDomain
  local domain="$1" key="$2"; shift 2
  defaults write "$domain" "$key" "$@" 2>/dev/null \
    || _log_warn "Could not set ${color_blue}$domain $key"
}

function _configure_macos_keyboard {
  # KeyRepeat=2 is faster than the System Settings slider can go.
  _defw -g KeyRepeat -int 2
  _defw -g InitialKeyRepeat -int 15
  # Holding a key repeats it instead of opening the accent picker -- required
  # for vim-style navigation to feel right in every text field.
  _defw -g ApplePressAndHoldEnabled -bool false
  _log_info "macOS: fast key repeat, press-and-hold off"
}

function _configure_macos_finder {
  _defw -g AppleShowAllExtensions -bool true
  _defw com.apple.finder ShowPathbar -bool true
  _defw com.apple.finder ShowStatusBar -bool true
  _defw com.apple.finder DisableAllAnimations -bool true
  _defw com.apple.finder FXPreferredViewStyle -string clmv  # column view
  _defw com.apple.finder FXDefaultSearchScope -string SCcf  # search this folder
  _defw com.apple.finder NewWindowTarget -string PfHm       # new windows open ~
  _defw com.apple.finder ShowHardDrivesOnDesktop -bool true
  _defw com.apple.finder ShowExternalHardDrivesOnDesktop -bool true
  _defw com.apple.finder ShowRemovableMediaOnDesktop -bool false
  _log_info "macOS: Finder column view, path + status bar, all extensions"
}

function _configure_macos_dock {
  _defw com.apple.dock orientation -string left
  _defw com.apple.dock tilesize -int 41
  _defw com.apple.dock autohide -bool false
  _defw com.apple.dock show-recents -bool false
  _defw com.apple.dock mru-spaces -bool false   # never reorder spaces (yabai)
  _defw com.apple.dock showLaunchpadGestureEnabled -bool false
  _defw com.apple.dock showAppExposeGestureEnabled -bool true
  _log_info "macOS: Dock on the left, 41px, no recents, fixed space order"
}

function _configure_macos_trackpad {
  # Tap-to-click lives in three places: the built-in trackpad, external
  # Bluetooth ones, and a global mirror that the login window reads.
  _defw com.apple.AppleMultitouchTrackpad Clicking -bool true
  _defw com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
  _defw -g com.apple.mouse.tapBehavior -int 1
  _defw com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true
  # Three-finger swipes stay off so skhd/yabai own space switching.
  _defw com.apple.AppleMultitouchTrackpad TrackpadThreeFingerHorizSwipeGesture -int 0
  _defw com.apple.AppleMultitouchTrackpad TrackpadThreeFingerVertSwipeGesture -int 0
  _log_info "macOS: tap to click, three-finger drag, no swipe gestures"
}

# com.apple.symbolichotkeys is one nested dict keyed by numeric action id, so a
# plain `defaults write` of a single id would clobber every other one. Export
# the whole domain, merge in Python, import it back.
#
#   64, 65   Spotlight and its Finder search window -> OFF, which is what frees
#            cmd-space for Alfred. This is the setting people forget.
#   60       select previous input source (cmd-space)      -> OFF, same reason
#   61       select next input source (cmd-opt-space)      -> ON
#   164      Launchpad                                     -> OFF
#   15-26    the Universal Access zoom / contrast / invert hotkeys -> OFF; they
#            collide with everything and only ever fire by accident.
function _configure_macos_hotkeys {
  command -v python3 >/dev/null 2>&1 \
    || { _log_warn "No python3; skipping ${color_blue}symbolichotkeys"; return 0; }

  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/symbolichotkeys.XXXXXX")" || return 0

  if ! defaults export com.apple.symbolichotkeys - 2>/dev/null \
       | python3 -c '
import plistlib, sys

OFF = list(range(15, 27)) + [60, 64, 65, 164]
ON  = [61]

raw = sys.stdin.buffer.read()
try:
    root = plistlib.loads(raw) if raw.strip() else {}
except Exception:
    root = {}
if not isinstance(root, dict):
    root = {}

keys = root.setdefault("AppleSymbolicHotKeys", {})
for i in OFF:
    keys.setdefault(str(i), {})["enabled"] = False
for i in ON:
    keys.setdefault(str(i), {})["enabled"] = True

sys.stdout.buffer.write(plistlib.dumps(root))
' > "$tmp"; then
    _log_warn "Could not build the symbolichotkeys plist; leaving it alone"
    rm -f "$tmp"
    return 0
  fi

  # Sanity check: never import an empty or truncated plist over the domain.
  if ! plutil -lint "$tmp" >/dev/null 2>&1 || [[ ! -s "$tmp" ]]; then
    _log_warn "Generated symbolichotkeys plist is not valid; leaving it alone"
    rm -f "$tmp"
    return 0
  fi

  if ! defaults import com.apple.symbolichotkeys "$tmp"; then
    _log_warn "Could not import ${color_blue}com.apple.symbolichotkeys"
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"

  # Read it back through cfprefsd rather than trusting the write: if System
  # Settings is open on the Keyboard pane it holds the domain and silently
  # reverts an import.
  local still_on
  still_on="$(defaults export com.apple.symbolichotkeys - 2>/dev/null \
    | python3 -c '
import plistlib, sys
raw = sys.stdin.buffer.read()
try:
    keys = plistlib.loads(raw).get("AppleSymbolicHotKeys", {})
except Exception:
    sys.exit(0)        # unreadable: fail open rather than cry wolf
print(",".join(i for i in ("60", "64", "65")
               if keys.get(i, {}).get("enabled", True)))
' 2>/dev/null)"
  if [[ -n "$still_on" ]]; then
    _log_warn "symbolichotkeys ${color_blue}$still_on${color_reset} did not stick -- close System Settings and re-run"
    return 0
  fi

  # SystemUIServer only reads this domain at launch, so without a restart the
  # Spotlight shortcut keeps working and cmd-space stays taken -- which is
  # exactly the "I had to turn it off by hand" failure. Restart it here rather
  # than at the end of configure_macos_defaults, which is skippable: this one
  # is not cosmetic, the setting simply does not take effect otherwise.
  if killall SystemUIServer >/dev/null 2>&1; then
    _log_info "macOS: Spotlight hotkey off (cmd-space is free for Alfred), Launchpad + zoom hotkeys off"
  else
    _log_info "macOS: Spotlight hotkey off in prefs"
    _log_warn "Could not restart SystemUIServer: cmd-space stays bound to Spotlight until you log out"
  fi
}

function configure_macos_defaults {
  is_mac || return 0

  # Stop Photos / Image Capture from auto-launching and grabbing a tethered
  # camera's single PTP session on connect -- the main cause of EOS Utility
  # freezing or failing to detect the R5. Per-host (does not sync via iCloud),
  # so it must be set once on each Mac. See bin/scripts/eos-fix for recovery.
  if defaults -currentHost write com.apple.ImageCapture disableHotPlug -bool YES; then
    _log_info "Disabled camera hot-plug auto-launch (Image Capture)"
  else
    _log_warn "Could not set Image Capture disableHotPlug"
  fi

  _configure_macos_keyboard
  _configure_macos_finder
  _configure_macos_dock
  _configure_macos_trackpad
  _configure_macos_hotkeys

  # Dock and Finder re-read their prefs only on launch, and relaunch
  # themselves immediately; nothing the user is working in gets touched.
  # These two are cosmetic-pending -- the settings are already written and
  # will appear at the next login anyway -- so MACOS_NO_RESTART_UI=1 skips
  # them. It does NOT skip the SystemUIServer restart in
  # _configure_macos_hotkeys: that one is load-bearing, the Spotlight hotkey
  # stays bound to cmd-space until SystemUIServer is restarted.
  if [[ -z "${MACOS_NO_RESTART_UI:-}" ]]; then
    for agent in Dock Finder; do
      killall "$agent" >/dev/null 2>&1
    done
    _log_info "Restarted Dock and Finder to apply the new defaults"
  else
    _log_warn "MACOS_NO_RESTART_UI set: log out and back in for the defaults to apply"
  fi

  _log_warn "Manual, cannot be scripted: grant ${color_blue}Karabiner-Elements${color_reset} Input Monitoring (that is what makes caps_lock an escape)"
  _log_warn "Manual, cannot be scripted: set Alfred's hotkey to ${color_blue}cmd-space${color_reset} (Alfred > Preferences > General)"
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

function ensure_xcode_clt {
  # Homebrew (and git) need the Command Line Tools. `xcode-select --install`
  # only *launches* a GUI installer and returns immediately, so waiting is on
  # us -- otherwise the first brew/git call races an incomplete install.
  is_mac || return 0

  if xcode-select -p >/dev/null 2>&1 && [[ -d "$(xcode-select -p 2>/dev/null)" ]]; then
    _log_btw "Already installed: ${color_blue}Xcode Command Line Tools${color_reset}. Skipping!"
    return 0
  fi

  _log_info "Installing ${color_blue}Xcode Command Line Tools${color_reset}"
  xcode-select --install 2>/dev/null

  _log_info "Waiting for the Command Line Tools installer to finish (accept the GUI prompt)"
  local waited=0
  while ! xcode-select -p >/dev/null 2>&1; do
    sleep 10
    waited=$((waited + 10))
    if (( waited % 60 == 0 )); then
      _log_btw "still waiting for Command Line Tools... (${waited}s)"
    fi
    if (( waited >= 1800 )); then
      _fail_error "Command Line Tools did not finish installing after 30 minutes"
      return 1
    fi
  done
  _log_info "Command Line Tools ready at ${color_blue}$(xcode-select -p)${color_reset}"
}

function ensure_homebrew {
  # This script calls `brew` in many places but historically assumed it was
  # already present -- on a brand new Mac that fails at the first package.
  # Install it if missing, and make it usable in THIS shell: the installer
  # does not touch the PATH of the running session.
  is_mac || return 0

  local brew_bin=""
  if command -v brew >/dev/null 2>&1; then
    brew_bin="$(command -v brew)"
  elif [[ -x /opt/homebrew/bin/brew ]]; then       # Apple Silicon
    brew_bin=/opt/homebrew/bin/brew
  elif [[ -x /usr/local/bin/brew ]]; then          # Intel
    brew_bin=/usr/local/bin/brew
  fi

  if [[ -z "$brew_bin" ]]; then
    _log_info "Installing ${color_blue}Homebrew${color_reset}"
    # NONINTERACTIVE avoids the "press RETURN" prompt; the installer still
    # asks for sudo once to create /opt/homebrew.
    if ! NONINTERACTIVE=1 /bin/bash -c \
        "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"; then
      _fail_error "Failed to install ${color_blue}Homebrew"
      return 1
    fi
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
      [[ -x "$candidate" ]] && brew_bin="$candidate" && break
    done
    [[ -z "$brew_bin" ]] && { _fail_error "Homebrew installed but ${color_blue}brew${color_reset} not found"; return 1; }
  else
    _log_btw "Already installed: ${color_blue}Homebrew${color_reset} ($brew_bin). Skipping!"
  fi

  # Put brew on PATH for the remainder of this run (idempotent).
  eval "$("$brew_bin" shellenv)"

  command -v brew >/dev/null 2>&1 \
    || { _fail_error "${color_blue}brew${color_reset} still not on PATH after shellenv"; return 1; }
}

TODOs=(
  "Mac App Store apps still need a human: Things 3, MindNode, Final Cut Pro"
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

# macOS prerequisites. Must run before any _install_package call, since the
# macOS path of _install_package shells out to `brew`.
ensure_xcode_clt
ensure_homebrew

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

install_brew_bundle      # macOS only: GUI apps (casks) from the Brewfile

configure_macos_defaults  # no-op on non-macOS

install_kitty_icon       # macOS only: nicer kitty.app icon

setup_login_shell        # macOS only: modern Homebrew bash as login shell

setup_neovim_venv

setup_tmux_plugins       # clone TPM + plugins into dots/config/tmux/plugins

_log_info "Bootstrapping complete! 🎉 "

if is_wsl; then
  _log_warn "You're running in WSL! Run ${color_blue}~/dots/bootstrap_windows.sh${color_reset} to set up Windows apps and WSL extras."
fi
