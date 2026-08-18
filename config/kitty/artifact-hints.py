# artifact-hints.py — kitty "hints" customization that overlays leap/flit-style
# labels beside every Meta diff/task ref (Dxxxxxxx / Txxxxxxx) on screen and
# opens the picked one in the browser. Invoked as:
#
#     kitten hints --customize-processing artifact-hints.py
#
# (wired to the ⌘I → o menu entry; also works standalone). Unlike a flat list,
# the labels appear in place, in context. Negative lookbehind avoids matching
# the D/T inside a longer identifier (e.g. the S,D in "SD1234567").
import re

ARTIFACT_RE = re.compile(r"(?<![A-Za-z0-9])([DT])(\d{7,})")
URLS = {
    "D": "https://www.internalfb.com/diff/D{num}",
    "T": "https://www.internalfb.com/tasks/?t={num}",
}


def mark(text, args, Mark, extra_cli_args, *a):
    for idx, m in enumerate(ARTIFACT_RE.finditer(text)):
        start, end = m.span()
        mark_text = text[start:end].replace("\n", "").replace("\0", "")
        yield Mark(idx, start, end, mark_text,
                   {"kind": m.group(1), "num": m.group(2)})


def handle_result(args, data, target_window_id, boss, extra_cli_args, *a):
    for m, g in zip(data["match"], data["groupdicts"]):
        if m and g.get("kind") in URLS:
            boss.open_url(URLS[g["kind"]].format(num=g["num"]))
