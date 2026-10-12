#!/bin/bash
# Install the Mac GUI apps from dots/Brewfile, and print the ones a human still
# has to fetch by hand.
#
# This is the standalone version of bootstrap.sh's install_brew_bundle -- use it
# when you only want the apps, e.g. on a freshly provisioned machine where the
# rest of the bootstrap already ran.
#
#   bash ~/dots/scripts/mac_apps.sh           # dry run: list what is missing
#   bash ~/dots/scripts/mac_apps.sh --go      # actually install
#
# Stock /bin/bash is 3.2 on macOS; keep this script compatible with it.

set -uo pipefail

GO="${1:-}"
if [ -n "$GO" ] && [ "$GO" != "--go" ]; then
  echo "usage: bash $0 [--go]" >&2
  exit 2
fi

DOTS="${DOTS_DIR:-$HOME/dots}"
BREWFILE="$DOTS/Brewfile"

[ -f "$BREWFILE" ] || { echo "ERROR: no $BREWFILE" >&2; exit 1; }

if ! command -v brew >/dev/null 2>&1; then
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$candidate" ] && eval "$("$candidate" shellenv)" && break
  done
fi
command -v brew >/dev/null 2>&1 || {
  echo "ERROR: Homebrew is not installed. Run ~/dots/bootstrap.sh first, or:" >&2
  echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"' >&2
  exit 1
}

# ------------------------------------------------------------------ missing?
missing=""
for cask in $(grep '^cask ' "$BREWFILE" | sed 's/^cask *"//; s/".*//'); do
  if brew list --cask "$cask" >/dev/null 2>&1; then
    printf '  ok      %s\n' "$cask"
  else
    printf '  MISSING %s\n' "$cask"
    missing="$missing $cask"
  fi
done

if [ -z "$missing" ]; then
  echo
  echo "All casks in the Brewfile are already installed."
else
  echo
  echo "Missing:$missing"
  if [ "$GO" = "--go" ]; then
    echo
    echo ">>> brew bundle install (casks may prompt for your password)"
    brew bundle install --file="$BREWFILE" --no-upgrade
  else
    echo
    echo "Dry run. Re-run with --go to install, or just:"
    echo "  brew install --cask$missing"
  fi
fi

# --------------------------------------------------- what brew cannot install
cat <<'MANUAL'

------------------------------------------------------------------------
Not available via Homebrew -- fetch these by hand:

  Mac App Store (sign in, then "Purchased"):
    Things 3            https://culturedcode.com/things/
    MindNode            https://www.mindnode.com/
    Final Cut Pro       (App Store, paid)
    Dashbar             (App Store, no cask)
    Keynote / Pages / Numbers   (usually preinstalled)

  Vendor download:
    Wally               https://ergodox-ez.com/pages/wally   (ZSA flasher;
                        Keymapp is the newer one and IS in the Brewfile)
    AvocadoApp          (no cask)

  Has a cask but left out of the Brewfile as situational:
    brew install --cask meta-quest-remote-desktop

  Meta-managed -- do NOT install by hand, they come from provisioning and
  Managed Software Center, and side-loading them fights MDM:
    Santa, Cyberhaven, NoMAD, ClientPlatformAssistant, VS Code @ FB,
    Flipper, MetaCodex, Microsoft Defender/Outlook, Slack 2, WAU,
    Help@ Remote Support, fido2-macos, Webex, Cisco Secure Client
------------------------------------------------------------------------

After installing, two things still need a human (no API for them):
  1. System Settings > Privacy & Security > Input Monitoring: enable
     Karabiner-Elements. That is what makes caps_lock an escape; the
     mapping itself is already in dots/config/karabiner/karabiner.json.
  2. Alfred > Preferences > General: set the hotkey to cmd-space.
     bootstrap.sh already turned Spotlight's cmd-space off for you.
MANUAL
