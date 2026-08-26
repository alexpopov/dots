# ===========================================================================
# hotkeys_config.py — the menu for the kitty modal hotkey launcher.
#
# THIS is the file you edit. The engine lives in hotkeys.py; you shouldn't
# need to touch it. Edits take effect on the next leader press (default cmd+i)
# — no reload needed.
#
# Press the leader, a little panel floats over the current terminal, then you
# press keys to run things or dive into submodes — like tmux's prefix or the
# skhd/yabai modal UI elsewhere in these dotfiles
# (config/hammerspoon/alex/skhd_ui.lua).
#
# ---------------------------------------------------------------------------
# THE MODEL (all you need to know)
# ---------------------------------------------------------------------------
# MODES maps a mode-name -> a mode. Every mode has a title and a set of key
# bindings. A binding is:  "<key>": (<description>, <action>)
#
# Actions — the verbs:
#
#   act("next_tab")                 Run a kitty "mappable action" — ANY action
#                                   from https://sw.kovidgoyal.net/kitty/actions/
#                                   e.g. act("change_font_size all +1.0").
#                                   Explore with `kitten @ action --help`.
#
#   rc("set-tab-title", "Build")    Run a raw remote-control command (things
#                                   under `kitten @ <cmd>`), one arg per string.
#
#   sh("open -a Safari")            Run a shell command (fire-and-forget). If it
#                                   comes from ask(), the typed text is appended
#                                   (shell-quoted) as the final argument.
#
#   go("tabs")                      Transition to another mode (a submenu).
#                                   Backspace goes back up; esc closes.
#
#   ask("New tab title",            Prompt for a line of text, then append it as
#       rc("set-tab-title"))        the final argument of the given action.
#
#   copy("cmd_output")              Copy text from the terminal to the clipboard.
#                                   what ∈ {"cmd_output", "output", "screen",
#                                   "all"}:
#                                     cmd_output = last command line + its output
#                                     output     = last command's output only
#                                     screen     = everything on screen
#                                     all        = screen + scrollback
#                                   (cmd_output/output need shell integration.)
#
# STAY vs EXIT:
#   Running an action CLOSES the panel by default. Pass stay=True to keep it
#   open so you can repeat it (font nudges, tab moves). go(...) always stays;
#   ask(...) exits after submit; copy(...) stays to show a "✓ copied" note.
#   Sticky actions are marked ⟳ in the panel; submenus ›.
#
# KEYS:
#   A single character ("t", "H", "="). Uppercase = shift ("H" shows ⇧h).
#   Use the literal " " for the space bar. esc/backspace are reserved.
# ===========================================================================


# --- tiny DSL (returns plain dicts the engine understands) -----------------
def act(spec, stay=False):
    return {"kind": "action", "a": spec.split(), "stay": stay}


def rc(*argv, stay=False):
    return {"kind": "rc", "a": list(argv), "stay": stay}


def sh(cmd, stay=False):
    return {"kind": "shell", "cmd": cmd, "stay": stay}


def go(mode):
    return {"kind": "mode", "target": mode}


def ask(label, then):
    return {"kind": "prompt", "label": label, "then": then}


def copy(what="cmd_output"):
    return {"kind": "builtin", "name": "copy", "what": what}


def open_artifact(multi=False):
    # Scan the terminal's visible text for Meta diff/task/paste refs (Dxxxxxxx
    # / Txxxxxxx / Pxxxxxxx) and open them in the browser -- the in-menu port of iTerm's
    # ⌘-click Smart Selection. One match opens immediately; several show a
    # one-keypress picker. Rules/URLs live in hotkeys.py (_bi_open_artifact).
    # multi=True keeps the picker open, opening each pick in the background.
    d = {"kind": "builtin", "name": "open_artifact"}
    if multi:
        d["multi"] = True
    return d


# --- the menu --------------------------------------------------------------
MODES = {
    "root": {
        "title": "Kitty",
        "keys": {
            "t": ("Tabs",                go("tabs")),
            "f": ("Font",                go("font")),
            ",": ("rename tab",          ask("New tab title", rc("set-tab-title"))),
            "y": ("copy last cmd+output", copy("cmd_output")),
            "c": ("Copy",                go("copy")),
            "o": ("open diff/task/paste ↗",       open_artifact()),
            "O": ("open many diff/task/pastes ↗", open_artifact(multi=True)),
            "r": ("reload kitty config", act("load_config_file")),
        },
    },

    "tabs": {
        "title": "Tabs",
        "keys": {
            "n": ("new tab",        act("new_tab")),
            "x": ("close tab",      act("close_tab")),
            "l": ("next tab",       act("next_tab", stay=True)),
            "h": ("previous tab",   act("previous_tab", stay=True)),
            "L": ("move tab right", act("move_tab_forward", stay=True)),
            "H": ("move tab left",  act("move_tab_backward", stay=True)),
            ",": ("rename tab",     ask("New tab title", rc("set-tab-title"))),
        },
    },

    "font": {
        "title": "Font",
        "keys": {
            "=": ("bigger",   act("change_font_size all +1.0", stay=True)),
            "+": ("bigger",   act("change_font_size all +1.0", stay=True)),
            "-": ("smaller",  act("change_font_size all -1.0", stay=True)),
            "0": ("reset",    act("change_font_size all 0")),
        },
    },

    "copy": {
        "title": "Copy",
        "keys": {
            "y": ("last command + output", copy("cmd_output")),
            "o": ("last output only",      copy("output")),
            "s": ("whole screen",          copy("screen")),
            "a": ("screen + scrollback",   copy("all")),
        },
    },
}
