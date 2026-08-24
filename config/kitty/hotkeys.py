#!/usr/bin/env python3
# ===========================================================================
# hotkeys.py — engine for the kitty modal hotkey launcher.
#
# You almost certainly want hotkeys_config.py instead — that's where the menu
# is defined and documented. This file renders the panel, reads keys, and
# dispatches the actions your config describes.
#
# Bound in kitty.conf as:  map cmd+i kitten hotkeys.py
#
# DEBUGGING
#   Logs to  $XDG_STATE_HOME/kitty/hotkeys.log  (default
#   ~/.local/state/kitty/hotkeys.log).  Any exception is also shown on screen
#   (press a key to dismiss) instead of just flashing the overlay closed.
# ===========================================================================

import base64
import importlib.util
import json
import os
import re
import select
import shlex
import subprocess
import sys
import termios
import time
import traceback
import tty


# ── logging ────────────────────────────────────────────────────────────────
def _log_path():
    base = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    d = os.path.join(base, "kitty")
    try:
        os.makedirs(d, exist_ok=True)
    except OSError:
        d = "/tmp"
    return os.path.join(d, "hotkeys.log")


_LOGF = None


def log(msg):
    global _LOGF
    try:
        if _LOGF is None:
            _LOGF = open(_log_path(), "a", buffering=1)
        _LOGF.write(time.strftime("%H:%M:%S ") + str(msg) + "\n")
    except Exception:
        pass


log("---- module import ----")
try:
    from kittens.tui.handler import kitten_ui
    log("import kitten_ui: OK")
    _HAVE_KITTEN_UI = True
except Exception as e:  # pragma: no cover
    log(f"import kitten_ui FAILED: {e!r} — falling back to no-op decorator")
    _HAVE_KITTEN_UI = False

    def kitten_ui(**_kw):
        def deco(f):
            return f
        return deco


# ── palette (truecolor; a light "card" that reads on any theme) ─────────────
BG_PANEL = "\x1b[48;2;245;246;248m"
FG_TEXT  = "\x1b[38;2;45;45;50m"
FG_KEY   = "\x1b[38;2;60;100;175m"
FG_DESC  = "\x1b[38;2;70;72;80m"
FG_TITLE = "\x1b[38;2;40;95;165m"
FG_BORD  = "\x1b[38;2;120;140;175m"
FG_HINT  = "\x1b[38;2;140;145;155m"
FG_WARN  = "\x1b[38;2;170;90;40m"
FG_OK    = "\x1b[38;2;40;130;70m"
FG_MARK  = "\x1b[38;2;150;155;165m"
BOLD     = "\x1b[1m"
RESET    = "\x1b[0m"
LABEL_HL   = BOLD + "\x1b[38;2;255;255;255m" + "\x1b[48;2;200;60;60m"  # leap-style hint label
LABEL_DONE = BOLD + "\x1b[38;2;255;255;255m" + "\x1b[48;2;60;150;90m"  # queued (multi mode)
MODE_TAG   = BOLD + "\x1b[38;2;255;255;255m" + "\x1b[48;2;90;90;200m"  # top-right mode indicator
_CLOSE   = object()  # sentinel: a builtin returning this closes the whole menu

# ── panel layout — tweak these to taste ─────────────────────────────────────
PAD_X      = 4    # blank columns inside the left & right borders
PAD_TOP    = 1    # blank rows between the title and the first entry
PAD_BOTTOM = 1    # blank rows between the footer and the bottom border
ROW_GAP    = 0    # blank rows between entries (set 1 for an airier list)
COL_GAP    = 3    # columns between a key and its description
MIN_INNER  = 44   # minimum inner width, so a short menu isn't tiny


# ── terminal I/O via the controlling tty (robust vs. stdin redirection) ──────
_TTY_FD = None


def tty_fd():
    global _TTY_FD
    if _TTY_FD is None:
        try:
            _TTY_FD = os.open("/dev/tty", os.O_RDWR | os.O_NOCTTY)
            log("opened /dev/tty")
        except OSError as e:
            log(f"/dev/tty open failed: {e!r}; using stdin")
            _TTY_FD = sys.stdin.fileno()
    return _TTY_FD


def _out(s):
    try:
        os.write(tty_fd(), s.encode("utf-8"))
    except OSError as e:
        log(f"_out write failed: {e!r}")


def _term_size():
    for fd in (tty_fd(), 1, 0):
        try:
            sz = os.get_terminal_size(fd)
            if sz.columns and sz.lines:
                return sz.columns, sz.lines
        except OSError:
            continue
    return 80, 24


# ── config loading ──────────────────────────────────────────────────────────
def _kitten_dir(args):
    try:
        return os.path.dirname(os.path.abspath(__file__))  # noqa: F821
    except NameError:
        pass
    for a in (args or []):
        if isinstance(a, str) and a.endswith("hotkeys.py") and os.path.exists(a):
            return os.path.dirname(os.path.abspath(a))
    cfg = os.environ.get("KITTY_CONFIG_DIRECTORY")
    if cfg and os.path.isdir(cfg):
        return cfg
    try:
        from kitty.constants import config_dir
        if config_dir and os.path.isdir(config_dir):
            return config_dir
    except Exception as e:
        log(f"config_dir import failed: {e!r}")
    return os.path.expanduser("~/.config/kitty")


def _load_modes(args):
    path = os.path.join(_kitten_dir(args), "hotkeys_config.py")
    log(f"loading config from {path}")
    spec = importlib.util.spec_from_file_location("hotkeys_config", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.MODES


def key_display(k):
    if k == " ":
        return "\u2423"                 # ␣
    if k.isupper():
        return "\u21e7" + k.lower()     # ⇧h
    return k


def _marker(action):
    kind = action["kind"]
    if kind == "mode":
        return "\u203a"                 # ›
    if kind == "builtin":
        return "\u29c9"                 # ⧉ (copies)
    if action.get("stay"):
        return "\u21bb"                 # ⟳
    return " "


# ── rendering ──────────────────────────────────────────────────────────────
def _paint_backdrop(bg):
    # Reset SGR and clear to the terminal's DEFAULT background (respects theme,
    # never black). Then, if we captured the underlying window, repaint it so
    # the panel appears to float over the live terminal.
    #
    # NB: the tty is in RAW mode, so a bare "\n" is line-feed only (no carriage
    # return). We must position every line explicitly, or the screen staircases
    # off the right edge. Autowrap is disabled so over-long lines clip instead
    # of pushing everything down.
    _out(RESET + "\x1b[2J")
    if not bg:
        return
    _, rows = _term_size()
    _out("\x1b[?7l")
    for i, ln in enumerate(bg.split("\n")[:rows], start=1):
        _out(f"\x1b[{i};1H" + RESET + ln)
    _out("\x1b[?7h" + RESET)


def draw(mode, breadcrumb, note=None, bg=None):
    cols, lines = _term_size()
    entries = [(key_display(k), desc, _marker(action))
               for k, (desc, action) in mode["keys"].items()]

    keyw = max([len(kd) for kd, _, _ in entries] + [1])
    descw = max([len(d) for _, d, _ in entries] + [1])
    header = " " + breadcrumb + " "
    footer = "esc close \u00b7 \u232b back \u00b7 \u21bb repeats"

    inner = max(
        [MIN_INNER, len(header) + 1, PAD_X + len(footer) + PAD_X,
         PAD_X + keyw + COL_GAP + descw + 1 + PAD_X]
        + ([PAD_X + len(note) + PAD_X] if note else [])
    )
    n_entry_rows = len(entries) + max(0, len(entries) - 1) * ROW_GAP
    n_note = 2 if note else 0                      # blank separator + note line
    box_h = 2 + PAD_TOP + n_entry_rows + n_note + 1 + 1 + PAD_BOTTOM  # +sep +footer
    box_w = inner + 2
    x0 = max(1, (cols - box_w) // 2 + 1)
    y0 = max(1, (lines - box_h) // 2 + 1)

    _paint_backdrop(bg)

    row = y0
    _out(f"\x1b[{row};{x0}H" + BG_PANEL + FG_BORD + "\u256d" + RESET + BG_PANEL
         + FG_TITLE + BOLD + header + RESET + BG_PANEL + FG_BORD
         + "\u2500" * (inner - len(header)) + "\u256e" + RESET)
    row += 1

    def line(render):
        nonlocal row
        _out(f"\x1b[{row};{x0}H" + BG_PANEL + FG_BORD + "\u2502" + RESET + BG_PANEL)
        render()
        _out(BG_PANEL + FG_BORD + "\u2502" + RESET)
        row += 1

    def blank():
        line(lambda: _out(" " * inner))

    for _ in range(PAD_TOP):
        blank()

    for i, (kd, desc, mark) in enumerate(entries):
        def render(kd=kd, desc=desc, mark=mark):
            _out(" " * PAD_X + FG_KEY + BOLD + kd.ljust(keyw) + RESET + BG_PANEL
                 + " " * COL_GAP + FG_DESC + desc + RESET + BG_PANEL)
            pad = inner - PAD_X - keyw - COL_GAP - len(desc) - 1 - PAD_X
            _out(" " * pad + FG_MARK + mark + RESET + BG_PANEL + " " * PAD_X)
        line(render)
        for _ in range(ROW_GAP if i < len(entries) - 1 else 0):
            blank()

    if note:
        blank()
        color = FG_OK if note.startswith("\u2713") else FG_WARN
        line(lambda: _out(" " * PAD_X + color + note + RESET + BG_PANEL
                          + " " * (inner - PAD_X - len(note))))

    blank()  # separator before footer
    line(lambda: _out(" " * PAD_X + FG_HINT + footer + RESET + BG_PANEL
                      + " " * (inner - PAD_X - len(footer))))

    for _ in range(PAD_BOTTOM):
        blank()

    _out(f"\x1b[{row};{x0}H" + BG_PANEL + FG_BORD + "\u2570" + "\u2500" * inner + "\u256f" + RESET)
    _out(RESET + "\x1b[1;1H")


# ── input ────────────────────────────────────────────────────────────────
def read_key(fd):
    ch = os.read(fd, 1)
    if not ch:
        log("read_key: EOF on tty")
        return "quit"
    if ch == b"\x1b":
        if not select.select([fd], [], [], 0.03)[0]:
            return "quit"
        while select.select([fd], [], [], 0.005)[0]:
            os.read(fd, 1)
        return "ignore"
    if ch in (b"\r", b"\n"):
        return "enter"
    if ch in (b"\x7f", b"\x08"):
        return "back"
    if ch == b"\x03":
        return "quit"
    try:
        return ch.decode("utf-8")
    except UnicodeDecodeError:
        while select.select([fd], [], [], 0.005)[0]:
            os.read(fd, 1)
        return "ignore"


def prompt_line(label, fd, bg=None):
    buf = ""
    cols, lines = _term_size()
    box_w = max(len(label) + 4, 44)
    inner = box_w - 2
    x0 = max(1, (cols - box_w) // 2 + 1)
    y0 = max(1, lines // 2 - 1)

    def render():
        _paint_backdrop(bg)
        _out(f"\x1b[{y0};{x0}H" + BG_PANEL + FG_BORD + "\u256d" + "\u2500" * inner + "\u256e" + RESET)
        _out(f"\x1b[{y0+1};{x0}H" + BG_PANEL + FG_BORD + "\u2502" + RESET + BG_PANEL
             + " " + FG_TITLE + BOLD + label + RESET + BG_PANEL
             + " " * (inner - 1 - len(label)) + FG_BORD + "\u2502" + RESET)
        shown = (buf + "\u2588")[-(inner - 2):]
        _out(f"\x1b[{y0+2};{x0}H" + BG_PANEL + FG_BORD + "\u2502" + RESET + BG_PANEL
             + " " + FG_TEXT + shown + RESET + BG_PANEL
             + " " * (inner - 1 - len(shown)) + FG_BORD + "\u2502" + RESET)
        _out(f"\x1b[{y0+3};{x0}H" + BG_PANEL + FG_BORD + "\u2570" + "\u2500" * inner + "\u256f" + RESET)
        _out(f"\x1b[{y0+4};{x0}H" + FG_HINT + "  \u21b5 save \u00b7 esc cancel" + RESET)
        _out(RESET + "\x1b[1;1H")

    render()
    while True:
        ch = os.read(fd, 1)
        if not ch:
            return None
        if ch in (b"\r", b"\n"):
            return buf
        if ch == b"\x1b":
            if not select.select([fd], [], [], 0.03)[0]:
                return None
            while select.select([fd], [], [], 0.005)[0]:
                os.read(fd, 1)
            continue
        if ch == b"\x03":
            return None
        if ch in (b"\x7f", b"\x08"):     # backspace
            buf = buf[:-1]
            render()
            continue
        if ch == b"\x17":                # C-w: delete word before cursor
            j = len(buf)
            while j > 0 and buf[j - 1].isspace():
                j -= 1
            while j > 0 and not buf[j - 1].isspace():
                j -= 1
            buf = buf[:j]
            render()
            continue
        if ch == b"\x15":                # C-u: clear the line
            buf = ""
            render()
            continue
        try:
            c = ch.decode("utf-8")
        except UnicodeDecodeError:
            extra = bytearray(ch)
            while select.select([fd], [], [], 0.005)[0]:
                extra += os.read(fd, 1)
            try:
                c = extra.decode("utf-8")
            except UnicodeDecodeError:
                continue
        if c.isprintable():
            buf += c
            render()


# ── target-window resolution (the window the leader was pressed in) ──────────
def resolve_target(rc):
    if rc is None:
        return None
    try:
        cp = rc(["ls"], capture_output=True)
        if cp.returncode != 0:
            log(f"ls rc={cp.returncode}")
            return None
        data = json.loads(cp.stdout)
    except Exception as e:
        log(f"ls failed: {e!r}")
        return None

    def tab_target(tab):
        wins = tab.get("windows", [])
        by_id = {w.get("id"): w for w in wins}
        non_self = [w for w in wins if not w.get("is_self")]
        if not non_self:
            return None
        for wid in tab.get("active_window_history", []) or []:
            w = by_id.get(wid)
            if w is not None and not w.get("is_self"):
                return wid
        for w in non_self:
            if w.get("is_active") or w.get("is_focused"):
                return w.get("id")
        return non_self[0].get("id")

    for osw in ([o for o in data if o.get("is_focused")] or data):
        for tab in ([t for t in osw.get("tabs", []) if t.get("is_focused")] or osw.get("tabs", [])):
            wid = tab_target(tab)
            if wid is not None:
                log(f"resolved target window id: {wid}")
                return wid
    log("resolve_target: no non-self window found")
    return None


def capture_backdrop(rc, target):
    if rc is None or target is None:
        return None
    try:
        cp = rc(["get-text", "--match", f"id:{target}", "--extent", "screen", "--ansi"],
                capture_output=True)
        if cp.returncode == 0:
            return cp.stdout.decode("utf-8", "replace")
        log(f"backdrop get-text rc={cp.returncode}")
    except Exception as e:
        log(f"backdrop get-text raised: {e!r}")
    return None


# ── dispatch ─────────────────────────────────────────────────────────────
def _run_rc(rc, argv):
    if rc is None:
        return "remote control unavailable"
    try:
        cp = rc(argv, capture_output=True)
    except Exception as e:
        log(f"rc {argv} raised: {e!r}")
        return str(e)[:60]
    if cp.returncode != 0:
        err = (cp.stderr or b"").decode("utf-8", "replace").strip()
        log(f"rc {argv} rc={cp.returncode} err={err!r}")
        return (err.splitlines()[-1] if err else "error")[:70]
    return None


def run_action(action, rc, target, text=None):
    kind = action["kind"]
    log(f"run_action kind={kind} target={target} text={text!r} action={action}")
    if kind == "shell":
        cmd = action["cmd"]
        if text is not None:
            cmd = cmd + " " + shlex.quote(text)
        try:
            subprocess.Popen(cmd, shell=True)
        except Exception as e:
            return str(e)[:60]
        return None
    if kind == "action":
        rest = list(action["a"]) + ([text] if text is not None else [])
        argv = ["action"]
        if target:
            argv += ["--match", f"id:{target}"]
        argv += rest
        return _run_rc(rc, argv)
    if kind == "rc":
        argv = list(action["a"]) + ([text] if text is not None else [])
        return _run_rc(rc, argv)
    return f"unknown action kind: {kind}"


# ── builtins (custom Python actions) ─────────────────────────────────────
def _set_clipboard(text):
    for cmd in (["pbcopy"], ["wl-copy"], ["xclip", "-selection", "clipboard"]):
        try:
            subprocess.run(cmd, input=text.encode("utf-8"), check=True,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            log(f"clipboard via {cmd[0]}")
            return True
        except Exception:
            continue
    try:  # OSC-52 fallback (works over the tty, incl. remote)
        b = base64.b64encode(text.encode("utf-8")).decode("ascii")
        _out("\x1b]52;c;" + b + "\x07")
        log("clipboard via OSC-52")
        return True
    except Exception as e:
        log(f"clipboard failed: {e!r}")
        return False


def _with_command_line(full, out):
    # last_cmd_output is output only; recover the command line printed just
    # above it in the full buffer.
    out_s = (out or "").rstrip("\n")
    if not out_s:
        return out or ""
    if not full:
        return out_s
    idx = full.rfind(out_s)
    if idx <= 0:
        return out_s
    before = full[:idx].rstrip("\n")
    if not before:
        return out_s
    return before.rsplit("\n", 1)[-1] + "\n" + out_s


# The tmux prefix + the key bound to "copy last command + output" in
# tmux.conf. If this window is running tmux, ⌘I y just injects these so tmux's
# own OSC-133 capture does the work (kitty can't see command marks through
# tmux). Update if you change the tmux prefix or that binding.
TMUX_COPY_KEYS = ("ctrl+s", "y")


def _window_runs_tmux(rc, target):
    if rc is None or target is None:
        return False
    try:
        cp = rc(["ls", "--match", f"id:{target}"], capture_output=True)
        if cp.returncode != 0:
            return False
        data = json.loads(cp.stdout)
    except Exception as e:
        log(f"_window_runs_tmux ls failed: {e!r}")
        return False
    for osw in data:
        for tab in osw.get("tabs", []):
            for w in tab.get("windows", []):
                for p in (w.get("foreground_processes") or []):
                    if any("tmux" in (c or "") for c in (p.get("cmdline") or [])):
                        return True
    return False


def _bi_copy(action, rc, target, fd=None, bg=None):
    if target is None:
        return "\u26a0 couldn't find the terminal window"

    what = action.get("what", "cmd_output")

    # If the window is running tmux, kitty can't see OSC-133 command marks
    # through it -- so for the "last command + output" case, delegate to tmux's
    # own binding by injecting the prefix+key (see TMUX_COPY_KEYS).
    if what == "cmd_output" and _window_runs_tmux(rc, target):
        err = _run_rc(rc, ["send-key", "--match", f"id:{target}", *TMUX_COPY_KEYS])
        if err:
            return f"\u26a0 tmux delegate failed: {err}"
        return "\u2713 copied via tmux (last command + output)"

    def gt(extent):
        try:
            cp = rc(["get-text", "--match", f"id:{target}", "--extent", extent],
                    capture_output=True)
        except Exception as e:
            log(f"get-text {extent} raised: {e!r}")
            return None
        if cp.returncode != 0:
            log(f"get-text {extent} rc={cp.returncode} {(cp.stderr or b'')!r}")
            return None
        return cp.stdout.decode("utf-8", "replace")

    if what == "output":
        text = gt("last_cmd_output")
    elif what == "screen":
        text = gt("screen")
    elif what == "all":
        text = gt("all")
    else:  # cmd_output
        text = _with_command_line(gt("all") or gt("screen"), gt("last_cmd_output"))

    if not text or not text.strip():
        return "\u26a0 nothing to copy (shell integration enabled?)"
    text = text.rstrip("\n") + "\n"
    if not _set_clipboard(text):
        return "\u26a0 clipboard unavailable"
    return f"\u2713 copied {text.count(chr(10))} lines / {len(text)} chars"


# ── open Meta artifacts (Dxxxxxxx / Txxxxxxx) — ported from the iTerm2 Smart
# Selection rules in ~/dots/config/iterm2. This is the in-menu version of what
# used to be a standalone `kitten hints` binding: it scans the target window's
# visible text for diff/task refs and opens them in the browser. Doing it here
# (rather than launching the hints kitten) avoids nesting an interactive kitten
# under this overlay, and works the same inside tmux / over ssh because it
# reads the rendered screen. Left \b would still allow a match inside a longer
# identifier (the S,D in "SD1234567"), so use a negative lookbehind instead.
ARTIFACT_RE = re.compile(r"(?<![A-Za-z0-9])([DT])(\d{7,})")
ARTIFACT_URLS = {
    "D": "https://www.internalfb.com/diff/D{num}",
    "T": "https://www.internalfb.com/tasks/?t={num}",
}


def _open_url(url, background=False):
    # macOS 'open -g' opens in the background (browser doesn't steal focus) --
    # ideal for firing off several in a row. xdg-open has no such flag.
    macopen = ["open", "-g", url] if background else ["open", url]
    for cmd in (macopen, ["xdg-open", url]):
        try:
            # start_new_session=True detaches the opener into its own session so
            # it survives this kitten exiting right after (return _CLOSE). Without
            # it, the opener is in the kitten's process group and can be killed
            # before LaunchServices actually opens the browser -> nothing opens.
            subprocess.Popen(cmd, stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
            log(f"opened url via {cmd[0]}: {url}")
            return True
        except Exception:
            continue
    log(f"_open_url failed: {url}")
    return False


def _open_urls(urls, background=False):
    """Open several URLs at once (one focus event at most). macOS 'open' accepts
    multiple URLs; fall back to xdg-open one at a time."""
    urls = list(urls)
    if not urls:
        return True
    try:
        cmd = ["open"] + (["-g"] if background else []) + urls
        subprocess.Popen(cmd, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        log(f"opened {len(urls)} urls via open (bg={background})")
        return True
    except Exception as e:
        log(f"_open_urls via open failed: {e!r}")
    ok = True
    for u in urls:
        ok = _open_url(u, background=background) and ok
    return ok


def _open_artifact(kind, num, tok, background=False):
    url = ARTIFACT_URLS.get(kind, "").format(num=num)
    if url and _open_url(url, background=background):
        return f"\u2713 opening {tok}"
    return f"\u26a0 couldn't open {tok}"


def _screen_lines(rc, target):
    """Plain (no-ANSI) screen rows of the target window, for computing positions."""
    if rc is None or target is None:
        return []
    try:
        cp = rc(["get-text", "--match", f"id:{target}", "--extent", "screen"],
                capture_output=True)
        if cp.returncode != 0:
            log(f"_screen_lines get-text rc={cp.returncode}")
            return []
        return cp.stdout.decode("utf-8", "replace").split("\n")
    except Exception as e:
        log(f"_screen_lines raised: {e!r}")
        return []


_LEAP_ALPHABET = "sfnjklhodweimbuyvrgtaqpcxz"  # leap.nvim's label order (muscle memory)


def _artifact_labels(n):
    if n <= len(_LEAP_ALPHABET):
        return list(_LEAP_ALPHABET[:n])
    import itertools
    return ["".join(p) for p in itertools.product(_LEAP_ALPHABET, repeat=2)][:n]


def _bi_open_artifact(action, rc, target, fd=None, bg=None):
    """Leap-style picker: label every D\u2026/T\u2026 ref in place on our OWN backdrop
    (no second kitten, so nothing can cover the labels), then open the pick.
    With multi=True, keep the picker open and open each pick in the background
    (opened labels turn green); esc when done."""
    multi = bool(action.get("multi"))
    if target is None:
        return "\u26a0 couldn't find the terminal window"
    hits = []
    for i, line in enumerate(_screen_lines(rc, target)):
        for m in ARTIFACT_RE.finditer(line):
            hits.append({"row": i + 1, "col": m.end() + 1,  # just AFTER the ref
                         "kind": m.group(1), "num": m.group(2), "tok": m.group(0)})
    if not hits:
        return "\u26a0 no D\u2026 / T\u2026 reference on screen"
    # Always label (even a single hit) so there's a visible pick step and we
    # never silently open a browser tab.
    by_label = {}
    for h, lab in zip(hits, _artifact_labels(len(hits))):
        h["label"] = lab
        by_label[lab] = h

    cols, rows = _term_size()
    queued = []      # hits picked in multi mode; all opened at once on esc
    picked = set()   # labels already queued (drawn green)

    def draw_labels():
        _paint_backdrop(bg)                    # repaint the frozen terminal...
        _out("\x1b[?7l")
        for h in hits:                         # ...then stamp labels just AFTER each
            if h["row"] <= rows:               # ref, so its D/T type stays visible
                col = min(h["col"], max(1, cols - len(h["label"]) + 1))
                style = LABEL_DONE if h["label"] in picked else LABEL_HL
                _out(f"\x1b[{h['row']};{col}H" + style + h["label"] + RESET)
        if multi:                              # tiny mode indicator, top-right corner
            tag = f" SELECT \u00b7 {len(queued)} queued "
            _out(f"\x1b[1;{max(1, cols - len(tag) + 1)}H" + MODE_TAG + tag + RESET)
            hint = " type labels to queue \u00b7 esc opens them "
        else:
            hint = " open diff/task \u00b7 type a label \u00b7 esc cancels "
        _out(f"\x1b[{rows};1H" + BG_PANEL + FG_HINT + hint + RESET + "\x1b[?7h")

    draw_labels()
    typed = ""
    while True:
        k = read_key(fd)
        if k == "back" and typed:               # undo a partial 2-char label
            typed = ""
            continue
        if k in ("quit", "back") or (multi and k == "enter"):  # esc / \u21b5 / \u2303C: done
            if queued:                          # open the whole queue at once
                _open_urls([ARTIFACT_URLS.get(h["kind"], "").format(num=h["num"])
                            for h in queued], background=True)
            return _CLOSE
        if k in ("enter", "ignore") or len(k) != 1:
            continue
        typed += k
        cands = [lab for lab in by_label if lab.startswith(typed)]
        if not cands:
            typed = ""
            continue
        if typed in by_label and len(cands) == 1:
            h = by_label[typed]
            if not multi:
                _open_artifact(h["kind"], h["num"], h["tok"])
                return _CLOSE
            if typed not in picked:             # queue it; opened together on esc
                picked.add(typed)
                queued.append(h)
            typed = ""
            draw_labels()                       # reflect queued (green) + count


BUILTINS = {"copy": _bi_copy, "open_artifact": _bi_open_artifact}


# ── error page (so failures don't just flash) ────────────────────────────
def _show_error(text):
    try:
        fd = tty_fd()
        try:
            old = termios.tcgetattr(fd)
            tty.setcbreak(fd)
        except Exception:
            old = None
        _out("\x1b[?1049h\x1b[?25h\x1b[2J\x1b[H")
        _out(FG_WARN + BOLD + "hotkeys kitten error\r\n\r\n" + RESET)
        for ln in str(text).splitlines():
            _out(ln + "\r\n")
        _out("\r\n\x1b[2mlogged to " + _log_path() + "\r\npress any key to close\x1b[0m\r\n")
        try:
            os.read(fd, 1)
        except Exception:
            pass
        _out("\x1b[?1049l")
        if old is not None:
            try:
                termios.tcsetattr(fd, termios.TCSADRAIN, old)
            except Exception:
                pass
    except Exception as e:
        log(f"_show_error failed: {e!r}")


# ── main ─────────────────────────────────────────────────────────────────
@kitten_ui(allow_remote_control=True)
def main(args):
    log(f"=== launch args={args!r} win={os.environ.get('KITTY_WINDOW_ID')!r} "
        f"have_kitten_ui={_HAVE_KITTEN_UI} ===")
    try:
        return _run(args)
    except Exception:
        tb = traceback.format_exc()
        log("EXCEPTION in main:\n" + tb)
        _show_error(tb)
        return ""


def _run(args):
    try:
        modes = _load_modes(args)
        log(f"loaded {len(modes)} modes: {list(modes)}")
    except Exception as e:
        tb = traceback.format_exc()
        log("config load failed:\n" + tb)
        _show_error(f"config error: {e}\n\n{tb}")
        return ""

    rc = getattr(main, "remote_control", None)
    log(f"remote_control present: {rc is not None}")
    target = resolve_target(rc)
    bg = capture_backdrop(rc, target)
    log(f"backdrop captured: {bg is not None}")

    fd = tty_fd()
    old = termios.tcgetattr(fd)
    tty.setraw(fd)
    _out("\x1b[?1049h\x1b[?25l")
    try:
        stack = ["root"]
        note = None
        while True:
            if stack[-1] not in modes:
                stack = ["root"]
            mode = modes[stack[-1]]
            crumb = " \u203a ".join(modes[m]["title"] for m in stack)
            draw(mode, crumb, note, bg)
            note = None

            key = read_key(fd)
            log(f"key={key!r} mode={stack[-1]}")
            if key == "quit":
                return ""
            if key == "back":
                if len(stack) > 1:
                    stack.pop()
                    continue
                return ""
            if key in ("enter", "ignore"):
                continue

            binding = mode["keys"].get(key)
            if binding is None:
                continue
            _desc, action = binding
            kind = action["kind"]

            if kind == "mode":
                if action["target"] in modes:
                    stack.append(action["target"])
                else:
                    note = f"unknown mode: {action['target']}"
                continue

            if kind == "builtin":
                fn = BUILTINS.get(action["name"])
                if fn is None:
                    note = f"unknown builtin: {action['name']}"
                else:
                    try:
                        note = fn(action, rc, target, fd=fd, bg=bg)
                    except Exception as e:
                        log("builtin error:\n" + traceback.format_exc())
                        note = f"error: {e}"
                if note is _CLOSE:
                    return ""
                continue  # otherwise stay so the ✓/⚠ note is visible

            if kind == "prompt":
                text = prompt_line(action["label"], fd, bg)
                if not text:
                    return ""
                err = run_action(action["then"], rc, target, text=text)
                if err:
                    note = err
                    continue
                return ""

            err = run_action(action, rc, target)
            if action.get("stay") or err:
                note = err
                continue
            return ""
    finally:
        _out("\x1b[?25h\x1b[?1049l")
        try:
            termios.tcsetattr(fd, termios.TCSADRAIN, old)
        except Exception:
            pass
        log("=== exit ===")
