# homebrew/bundle, homebrew/cask and homebrew/core are built in now; tapping
# them explicitly fails ("this tap is now empty / no longer necessary").
tap "koekeishiya/formulae"
brew "fd"
brew "fzf"
brew "git-lfs"
brew "lazygit"
brew "mosh"
brew "neovim"
brew "ripgrep"
# macOS 26 ships openrsync as /usr/bin/rsync: no --info, no -X, and it cannot
# overwrite an existing read-only file (every git pack object), so re-running a
# copy dies with EACCES. Real rsync 3 for machine-to-machine transfers.
brew "rsync"
brew "the_silver_searcher"
brew "tmux"
brew "tree"
brew "koekeishiya/formulae/skhd"
brew "koekeishiya/formulae/yabai"

# ---------------------------------------------------------------- casks
# GUI apps, personal machines only. Deliberately NOT here: anything that comes
# from Meta provisioning / Managed Software Center (Santa, Cyberhaven, NoMAD,
# ClientPlatformAssistant, VS Code @ FB, Flipper, MetaCodex, Defender, Outlook,
# Slack 2, WAU, Help@, fido2-macos) -- installing those by hand fights MDM.
# Also not here: App Store apps (Things 3, MindNode, Keynote/Pages/Numbers) and
# Wally, which has no cask. Grab those from the App Store / vendor.

# launcher + keyboard + window management: the stuff that makes a Mac usable
cask "alfred"               # replaces Spotlight; see configure_macos_defaults
cask "karabiner-elements"   # caps_lock -> escape; config lives in dots. pkg
                            # installer: needs a real sudo prompt, so this one
                            # cannot be installed over a non-interactive ssh.
cask "hammerspoon"          # config lives in dots
cask "divvy"
cask "maccy"                # clipboard history
cask "rocket"               # :emoji: anywhere
cask "captin"               # caps-lock state HUD
cask "choosy"               # per-link browser picker (pkg installer, needs sudo)
cask "keycastr"             # on-screen keystrokes, for recordings
cask "keymapp"              # ZSA keyboard config (Wally has no cask)

# terminals (all have configs in dots/config)
cask "kitty"
cask "ghostty"
cask "iterm2"
# wezterm: the stable cask is pinned to a 2024 build and refuses to install
# over a newer WezTerm.app ("bundle short version ... is 0.1.0"), which is
# exactly what a provisioned Mac has. Use `brew install --cask wezterm@nightly`
# or leave the existing one alone.

# dev
cask "google-chrome"
cask "android-studio"
cask "intellij-idea"
cask "cyberduck"
cask "figma"

# personal
cask "anki"
cask "notion"
cask "telegram"
cask "whatsapp"
cask "discord"
cask "superwhisper"
cask "steam"
cask "adobe-acrobat-reader" # pkg installer, needs sudo
cask "spark-app"            # email (the cask "spark" was renamed)
cask "textual"              # IRC
cask "there"                # timezones in the menu bar
