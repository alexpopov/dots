#!/bin/bash
# Bootstrap a Mac that has NOTHING on it yet -- no git, no Homebrew, no dots.
#
# This is the chicken-and-egg entry point: new_mac_bootstrap.sh and
# bootstrap.sh both live inside the repo, so something has to install git and
# clone the repo first. That is this script, and it is the only one you should
# ever need to curl.
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/alexpopov/dots/master/scripts/new_mac_from_scratch.sh)"
#
# Everything here is idempotent; re-running is safe.
#
# Deliberately written for the stock macOS /bin/bash (3.2): no associative
# arrays, no `mapfile`, nothing from a modern bash. A new Mac does not have
# Homebrew bash yet -- that is what we are here to install.

set -u

DOTS_REPO_HTTPS="https://github.com/alexpopov/dots.git"
DOTS_REPO_SSH="git@github.com:alexpopov/dots.git"
DOTS_DIR="$HOME/dots"

say()  { printf '\033[1;34m==>\033[m %s\n' "$1"; }
warn() { printf '\033[1;33m==> WARNING:\033[m %s\n' "$1"; }
die()  { printf '\033[1;31m==> ERROR:\033[m %s\n' "$1" >&2; exit 1; }

[ "$(uname -s)" = "Darwin" ] || die "This script is macOS-only."

# ── 1. Xcode Command Line Tools ───────────────────────────────────────────
# Needed for git (and for Homebrew). `xcode-select --install` only LAUNCHES a
# GUI installer and returns immediately, so we have to wait for it ourselves --
# otherwise the git clone below races an incomplete install.
if xcode-select -p >/dev/null 2>&1 && [ -d "$(xcode-select -p 2>/dev/null)" ]; then
  say "Xcode Command Line Tools already installed."
else
  say "Installing Xcode Command Line Tools (accept the GUI prompt)..."
  xcode-select --install 2>/dev/null
  waited=0
  while ! xcode-select -p >/dev/null 2>&1; do
    sleep 10
    waited=$((waited + 10))
    if [ $((waited % 60)) -eq 0 ]; then
      say "still waiting for Command Line Tools... (${waited}s)"
    fi
    [ "$waited" -ge 1800 ] && die "Command Line Tools did not install within 30 minutes."
  done
  say "Command Line Tools ready at $(xcode-select -p)"
fi

command -v git >/dev/null 2>&1 || die "git still not available after installing the CLT."

# ── 2. Homebrew ───────────────────────────────────────────────────────────
# bootstrap.sh installs this too, but we need brew on PATH for this shell and
# it is cheap to be certain before handing over.
BREW_BIN=""
if command -v brew >/dev/null 2>&1; then
  BREW_BIN="$(command -v brew)"
elif [ -x /opt/homebrew/bin/brew ]; then
  BREW_BIN=/opt/homebrew/bin/brew
elif [ -x /usr/local/bin/brew ]; then
  BREW_BIN=/usr/local/bin/brew
fi

if [ -z "$BREW_BIN" ]; then
  say "Installing Homebrew (one sudo prompt)..."
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    || die "Homebrew install failed."
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$candidate" ] && BREW_BIN="$candidate" && break
  done
  [ -n "$BREW_BIN" ] || die "Homebrew installed but brew not found."
else
  say "Homebrew already installed ($BREW_BIN)."
fi

# The installer does not touch the PATH of the running shell.
eval "$("$BREW_BIN" shellenv)"

# ── 3. The repo ───────────────────────────────────────────────────────────
# Clone over HTTPS: a brand new Mac has no SSH key enrolled with GitHub yet.
# If ~/.ssh was carried over and the key works, prefer SSH so pushes just work.
if [ -d "$DOTS_DIR/.git" ]; then
  say "dots already cloned at $DOTS_DIR -- pulling."
  git -C "$DOTS_DIR" pull --ff-only || warn "pull failed; continuing with what's on disk."
  git -C "$DOTS_DIR" submodule update --init --recursive || warn "submodule update failed."
else
  if [ -d "$DOTS_DIR" ]; then
    # A half-finished rsync leaves read-only git objects that confuse things.
    die "$DOTS_DIR exists but is not a git repo. Move it aside first:
       chmod -R u+w '$DOTS_DIR' && rm -rf '$DOTS_DIR'"
  fi
  REPO="$DOTS_REPO_HTTPS"
  if ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8 \
         -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
    say "GitHub SSH key works -- cloning over SSH."
    REPO="$DOTS_REPO_SSH"
  else
    say "No working GitHub SSH key -- cloning over HTTPS."
    say "  (switch later with: git -C $DOTS_DIR remote set-url origin $DOTS_REPO_SSH)"
  fi
  say "Cloning dots into $DOTS_DIR ..."
  git clone --recursive "$REPO" "$DOTS_DIR" || die "clone failed."
fi

# ── 4. Hand over to the real bootstrap ────────────────────────────────────
say "Handing over to new_mac_bootstrap.sh ..."
echo
exec bash "$DOTS_DIR/new_mac_bootstrap.sh"
