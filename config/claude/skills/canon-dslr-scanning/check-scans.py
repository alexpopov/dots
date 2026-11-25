#!/usr/bin/env -S uv run --quiet --script
# /// script
# dependencies = ["rawpy", "numpy"]
# ///
"""Check scan exposure from the raw data.

  check-scans.py FILE.CR3...     check specific files
  check-scans.py FOLDER          check every CR3 in a folder
  check-scans.py --watch [DIR]   stay running; print OK or NAY for each new CR3 that lands in DIR
                                 (default: today's ~/Pictures/YYYY_MM_DD). Run it in a tmux split.

OK  = brightest channel's 99.9th percentile is 70-95 % of full scale and nothing clips in the picture.
NAY = too dark (says how many stops to add) or clipped (says to shorten the shutter).
Clipped pixels are always located, with the question to ask: is the light pad visible there?
"""
import datetime, glob, os, subprocess, sys, time
import numpy as np, rawpy

CLIP, IDEAL_LO, TARGET = 0.985, 0.70, 0.88   # ponytail: fixed thresholds; tune here if the light source changes
CLIPPED_SHARE = 0.0005                        # more than this share of pixels at the ceiling counts as a real clip
GREEN, RED, BOLD, RESET = ("\033[32m", "\033[31m", "\033[1m", "\033[0m") if sys.stdout.isatty() else ("", "", "", "")

def check(path):
    """Return (ok, one-line report) for one raw file."""
    r = rawpy.imread(path)
    im = r.raw_image_visible.astype(np.float32); pat = r.raw_pattern; bl = r.black_level_per_channel; wl = r.white_level
    worst = None
    for i in range(2):
        for j in range(2):
            c = pat[i, j]; full = wl - bl[c]; v = im[i::2, j::2] - bl[c]
            hot = v >= full * CLIP
            where = ""
            if hot.any():   # always say where clipping is, so it can be audited rather than assumed harmless
                ys, xs = np.nonzero(hot); H, W = v.shape
                where = f"{int(hot.sum())} px at x {xs.min()/W*100:.0f}-{xs.max()/W*100:.0f}%, y {ys.min()/H*100:.0f}-{ys.max()/H*100:.0f}%"
            row = (np.percentile(v, 99.9) / full, v.max() / full, float(hot.mean()), r.color_desc.decode()[c], where)
            if worst is None or row[0] > worst[0]: worst = row
    p999, mx, clipped, ch, where = worst
    if clipped > CLIPPED_SHARE: ok, verdict = False, "CLIPPED: shorten the shutter"
    elif p999 < IDEAL_LO: ok, verdict = False, f"dark: add {np.log2(TARGET / p999):.1f} stops"
    else: ok, verdict = True, "good"
    if where: verdict += f"; clipped: {where} (is the light pad visible via the notch or an edge there?)"
    shutter = subprocess.run(["exiftool", "-q", "-T", "-ExposureTime", path], capture_output=True, text=True).stdout.strip() or "?"
    tag = f"{BOLD}{GREEN}OK {RESET}" if ok else f"{BOLD}{RED}NAY{RESET}"
    return ok, f"{tag} {os.path.basename(path):20s} {shutter:>5s}  {ch} {p999*100:5.1f}%  max {mx*100:5.1f}%  {verdict}"

def watch(folder):
    print(f"watching {folder} for new CR3 files (ctrl-c to stop)", flush=True)
    seen = set(glob.glob(os.path.join(folder, "*.CR3")))
    while True:
        time.sleep(1)
        for f in sorted(set(glob.glob(os.path.join(folder, "*.CR3"))) - seen):
            size = -1
            while size != os.path.getsize(f):   # wait until EOS Utility has finished writing the file
                size = os.path.getsize(f); time.sleep(1)
            seen.add(f)
            try:
                ok, line = check(f)
            except Exception as e:              # a half-written or unreadable file should not stop the watcher
                ok, line = False, f"NAY {os.path.basename(f)}: could not read ({e})"
            print(line + ("" if ok else "\a"), flush=True)   # bell on NAY

args = sys.argv[1:]
if args[:1] == ["--watch"]:
    folder = os.path.expanduser(args[1] if len(args) > 1 else datetime.date.today().strftime("~/Pictures/%Y_%m_%d"))
    os.makedirs(folder, exist_ok=True)
    try: watch(folder)
    except KeyboardInterrupt: pass
else:
    files = []
    for a in args or ["."]:
        files += sorted(glob.glob(os.path.join(a, "*.CR3"))) if os.path.isdir(a) else [a]
    if not files: sys.exit("no CR3 files")
    results = [check(f) for f in files]
    for _, line in results: print(line)
    sys.exit(0 if all(ok for ok, _ in results) else 1)
