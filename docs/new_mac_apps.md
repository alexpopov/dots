# Setting up a new Mac: apps and system settings

What is automated, what is not, and why. Written while migrating
`alexpopov-mbp` -> `alexpopov-mac` (Oct 2026).

## TL;DR

```bash
# from nothing: CLT -> Homebrew -> clone dots -> bootstrap
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/alexpopov/dots/master/scripts/new_mac_from_scratch.sh)"

# apps only, on a machine that is already bootstrapped
bash ~/dots/scripts/mac_apps.sh          # dry run, lists what is missing
bash ~/dots/scripts/mac_apps.sh --go     # install
```

`bootstrap.sh` now does three things it did not before:

| step | function | effect |
|---|---|---|
| `install_brew_bundle` | runs `brew bundle --no-upgrade` | installs every `cask` in `Brewfile` |
| `configure_macos_defaults` | keyboard / Finder / Dock / trackpad | values read off the old Mac, not invented |
| `_configure_macos_hotkeys` | merges `com.apple.symbolichotkeys` | turns Spotlight's cmd-space off so Alfred can have it |

All three are idempotent: `brew bundle check` short-circuits when everything is
present, `defaults write` is by definition a set-to-value, and the hotkey step
exports the existing domain, merges, and imports it back rather than
overwriting it.

## The apps

### Installed by `Brewfile` (just run bootstrap)

launcher / keyboard / windows
: `alfred` `karabiner-elements` `hammerspoon` `divvy` `maccy` `rocket`
  `captin` `choosy` `keycastr` `keymapp`

terminals (all four have configs in `dots/config`)
: `kitty` `ghostty` `wezterm` `iterm2`

dev
: `google-chrome` `android-studio` `intellij-idea` `cyberduck` `figma`

personal
: `anki` `notion` `telegram` `whatsapp` `discord` `superwhisper` `steam`
  `adobe-acrobat-reader` `spark` `textual` `there`

### Installed, but only from a terminal you are sitting in front of

`karabiner-elements`, `choosy` and `adobe-acrobat-reader` ship an installer
`.pkg`; `google-chrome` has to `chgrp` the bundle provisioning already put in
`/Applications`. All four shell out to `sudo`, which has no tty under a
scripted/ssh run, so they fail there and nowhere else:

```bash
brew install --cask karabiner-elements choosy adobe-acrobat-reader google-chrome
```

`bootstrap.sh` checks for exactly these at the end and prints the command.

### Needs a human

| app | where from | note |
|---|---|---|
| Things 3 | Mac App Store | paid, tied to the Apple ID |
| MindNode | Mac App Store | ditto |
| Final Cut Pro | Mac App Store | ditto |
| Dashbar | Mac App Store | no cask |
| AvocadoApp | vendor | no cask |
| Wally | <https://ergodox-ez.com/pages/wally> | ZSA flasher; `keymapp` is the newer one and *is* in the Brewfile |
| Meta Quest Remote Desktop | `brew install --cask meta-quest-remote-desktop` | a cask exists; left out of the Brewfile because it is situational |
| WezTerm | `brew install --cask wezterm@nightly` | the stable cask is pinned to a 2024 build and refuses to install over a newer WezTerm.app |

### Do NOT install by hand

These arrive from Provisioning @ Anywhere and Managed Software Center.
Side-loading them fights MDM:

> Santa, Cyberhaven, NoMAD, ClientPlatformAssistant, VS Code @ FB, Flipper,
> MetaCodex, Microsoft Defender, Microsoft Outlook, Slack 2, WAU,
> Help@ Remote Support, fido2-macos, Webex, Cisco Secure Client,
> Personal Print Manager, AppStreamer, Agent Conductor

## The system settings

Read off the old Mac with `defaults read`, then transcribed into
`configure_macos_defaults`. To change one: change it in System Settings, read
the new value, paste it in. Do not guess.

- **keyboard** — `KeyRepeat=2`, `InitialKeyRepeat=15` (both faster than the
  System Settings slider allows), `ApplePressAndHoldEnabled=false` so holding a
  key repeats instead of opening the accent picker.
- **Finder** — column view, path bar, status bar, all extensions, new windows
  open `~`, search scoped to the current folder, animations off.
- **Dock** — left, 41px, no recents, `mru-spaces=false` so spaces never
  reorder themselves under yabai.
- **trackpad** — tap to click (set in three domains: built-in, Bluetooth, and
  the global mirror the login window reads), three-finger drag on,
  three-finger swipes off because skhd/yabai own those.
- **hotkeys** — `com.apple.symbolichotkeys` ids 64 and 65 (Spotlight, Spotlight
  window) and 60 (previous input source) disabled, which is what actually frees
  cmd-space for Alfred; 164 (Launchpad) and 15-26 (Universal Access
  zoom/contrast/invert) disabled too.

`Dock`, `Finder` and `SystemUIServer` are restarted at the end so the changes
take effect; they are self-respawning UI agents, nothing a user is working in
gets touched. Set `MACOS_NO_RESTART_UI=1` to skip and log out instead.

## Still manual, by nature

1. **Karabiner-Elements needs Input Monitoring.** System Settings > Privacy &
   Security > Input Monitoring. The mapping itself
   (`caps_lock -> escape`, `escape -> f20`) is already in
   `dots/config/karabiner/karabiner.json`, symlinked by `create_links`. There
   is no API to grant TCC permissions; `tccutil` cannot do it either.
2. **Alfred's hotkey.** Alfred > Preferences > General > set to cmd-space.
   Bootstrap only frees the key.
3. **yabai's scripting addition** needs SIP partially disabled.
4. **App Store apps** need a signed-in Apple ID.

## App config that is not in dots

Most app settings live in `~/Library/Preferences/*.plist` and come across with
the migration's phase 4. Two that do *not* live there:

- `~/Library/Application Support/Alfred` — workflows, snippets, the lot. 16 K,
  copy it.
- `~/Library/Application Support/Anki2` — the collection. Irreplaceable.

Everything else worth keeping is already a symlink into `dots/config`:
nvim, kitty, ghostty, wezterm(ish), tmux, git, bash, skhd, yabai, hammerspoon,
karabiner, lazygit, pi, iterm2.
