#!/usr/bin/env bash
# Bootstrap a brand new Mac.
#
#   bash ~/dots/new_mac_bootstrap.sh
#
# Safe to re-run: every step is idempotent.

DOTS_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source colours from the repo, NOT from ~/.local/bin/scripts/ -- that path is
# a symlink created later by bootstrap.sh's create_links, so on a new machine
# it does not exist yet.
if [[ -r "$DOTS_SELF_DIR/bin/scripts/color.sh" ]]; then
  . "$DOTS_SELF_DIR/bin/scripts/color.sh"
fi

function run_main_bootstrap {
  local main_bootstrap="$DOTS_SELF_DIR/bootstrap.sh"
  echo "Running main bootstrap script..."
  echo "${main_bootstrap}"
  . "$main_bootstrap"
}

function install_brew_stuff {
  # bootstrap.sh (via ensure_xcode_clt / ensure_homebrew) has already installed
  # the Command Line Tools and Homebrew and put brew on PATH by this point.
  if ! command -v brew >/dev/null 2>&1; then
    echo "ERROR: brew not on PATH - bootstrap.sh should have installed it" >&2
    return 1
  fi
  pushd "$DOTS_SELF_DIR" >/dev/null || return 1
  brew bundle
  local rc=$?
  popd >/dev/null || true
  return $rc
}

# bootstrap.sh installs the Xcode CLT and Homebrew itself now (and waits for
# the CLT GUI installer to finish), so no xcode-select call is needed here --
# it used to run *after* the bootstrap, which was too late to be of any use.
run_main_bootstrap

install_brew_stuff || echo "brew bundle reported errors - see above"

echo 'To be continued...'
