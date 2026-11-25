#!/usr/bin/env -S uv run --quiet --script
# /// script
# dependencies = ["rawpy", "numpy"]
# ///
"""Write a darktable sidecar for a B&W negative scan from bw-negative-template.CR3.xmp.

usage: make-bw-sidecar.py FILE.CR3 [--auto] [--flip N] [--mono] [--wb R B] [--dmin V] [--dmax V]
                                   [--crop L T R B] [--inset F] [--out PATH]
  --auto     measure the scan itself (needs the black mask around the sheet) and set white balance,
             film base (D min), D max and a crop to the sheet. Explicit options below override it.
  --flip N   darktable orientation code 0-7 (bit 1 = flip vertically, 2 = flip horizontally, 4 = swap x/y).
             Scans shot emulsion side up are mirrored: 2 = mirror only, 7 = quarter turn + mirror.
  --mono     color balance rgb global chroma -100 % (true black and white); nothing else in that module changes
  --wb R B   white balance multipliers (green = 1), i.e. raw G/R and G/B of the film base
  --dmin V   negadoctor film-base level, --dmax V negadoctor D max
  --crop L T R B   crop edges as fractions of the final (oriented) image
  --inset F  with --auto: trim this fraction off each side of the detected sheet (default 0.03, hides rebate)
  --out PATH write here instead of FILE.CR3.xmp
Never write next to an image darktable has open: the app overwrites sidecars. Write elsewhere with --out
and push it with img:apply_sidecar() from the lighttable (see SKILL.md).
"""
import argparse, base64, os, re, struct, sys, zlib

ap = argparse.ArgumentParser()
ap.add_argument("cr3"); ap.add_argument("--auto", action="store_true"); ap.add_argument("--flip", type=int, default=0)
ap.add_argument("--mono", action="store_true"); ap.add_argument("--wb", nargs=2, type=float)
ap.add_argument("--dmin", type=float); ap.add_argument("--dmax", type=float)
ap.add_argument("--crop", nargs=4, type=float); ap.add_argument("--inset", type=float, default=0.03); ap.add_argument("--out")
a = ap.parse_args()

def measure(path, inset):
    """White balance, base level, D max and sheet bounding box (raw orientation, fractions) from the raw data."""
    import numpy as np, rawpy
    r = rawpy.imread(path); im = r.raw_image_visible.astype(np.float32); pat = r.raw_pattern; desc = r.color_desc.decode()
    ch = {}
    for i in range(2):
        for j in range(2):
            c = pat[i, j]; ch.setdefault(desc[c], np.maximum(im[i::2, j::2] - r.black_level_per_channel[c], 1))
    R, G, B = ch["R"], ch["G"], ch["B"]; full = r.white_level - r.black_level_per_channel[pat[0, 1]]; H, W = G.shape
    film = G > np.percentile(G, 99.9) * 0.02                      # everything brighter than the black mask
    cols = np.nonzero(film.mean(0) > 0.5)[0]; rows = np.nonzero(film.mean(1) > 0.5)[0]
    x0, x1, y0, y1 = cols[0] / W, (cols[-1] + 1) / W, rows[0] / H, (rows[-1] + 1) / H
    ok = film & (G < full * 0.97)                                  # film, not clipped (notches show bare pad)
    base = np.percentile(G[ok], 99.5)
    near = ok & (G >= np.percentile(G[ok], 97)) & (G <= base)      # pixels close to clear film base
    wb = (float(np.median(G[near] / R[near])), float(np.median(G[near] / B[near])))
    dx, dy = (x1 - x0), (y1 - y0)
    centre = G[int((y0 + 0.15 * dy) * H):int((y1 - 0.15 * dy) * H), int((x0 + 0.15 * dx) * W):int((x1 - 0.15 * dx) * W)]
    dmax = float(np.log10(base / np.percentile(centre, 1)))
    box = (x0 + inset * dx, y0 + inset * dy, x1 - inset * dx, y1 - inset * dy)
    return wb, float(base / full), max(0.5, dmax), box

def orient(box, code):
    """Map a (left, top, right, bottom) box from raw orientation to darktable orientation `code`.
    ponytail: swap-then-flip order, verified against renders for codes 0, 2 and 7 only."""
    l, t, r, b = box
    if code & 4: l, t, r, b = t, l, b, r
    if code & 2: l, r = 1 - r, 1 - l
    if code & 1: t, b = 1 - b, 1 - t
    return l, t, r, b

wb, dmin, dmax, crop = a.wb, a.dmin, a.dmax, a.crop
if a.auto:
    m_wb, m_base, m_dmax, m_box = measure(a.cr3, a.inset)
    wb = wb or m_wb; dmin = dmin if dmin is not None else m_base
    dmax = dmax if dmax is not None else m_dmax; crop = crop or orient(m_box, a.flip)

s = open(os.path.join(os.path.dirname(os.path.realpath(__file__)), "bw-negative-template.CR3.xmp")).read()

def dec(p): return zlib.decompress(base64.b64decode(p[4:])) if p.startswith("gz") else bytes.fromhex(p)

def edit(op, fn=None, enable=False):
    """Apply fn(bytes)->bytes to the params of every history entry of module `op`; optionally switch it on."""
    global s
    n = 0
    def one(m):
        nonlocal n
        li = m.group(0)
        if f'darktable:operation="{op}"' not in li: return li
        n += 1
        if fn:
            p = re.search(r'darktable:params="([^"]*)"', li).group(1)
            li = li.replace(f'darktable:params="{p}"', f'darktable:params="{fn(dec(p)).hex()}"')
        return li.replace('darktable:enabled="0"', 'darktable:enabled="1"') if enable else li
    s = re.sub(r"<rdf:li\b[^>]*?/>", one, s, flags=re.S)
    assert n, f"no {op} entry in template"

def put(fmt, off, *vals):
    def fn(b):
        assert len(b) >= off + struct.calcsize(fmt), (len(b), off)
        return b[:off] + struct.pack(fmt, *vals) + b[off + struct.calcsize(fmt):]
    return fn

if wb: edit("temperature", put("<4fi", 0, wb[0], 1.0, wb[1], 1.0, 2))   # preset 2 = user
edit("flip", put("<i", 0, a.flip))
if dmin is not None: edit("negadoctor", put("<3f", 4, dmin, dmin, dmin))
if dmax is not None: edit("negadoctor", put("<f", 52, dmax))
if crop: edit("crop", put("<4f", 0, *crop), enable=True)
if a.mono: edit("colorbalancergb", put("<f", 17 * 4, -1.0))            # chroma_global
s, n = re.subn(r'xmpMM:DerivedFrom="[^"]*"', f'xmpMM:DerivedFrom="{os.path.basename(a.cr3)}"', s); assert n == 1
out = a.out or a.cr3 + ".xmp"
if os.path.exists(out) and not a.out: sys.exit(f"{out} exists; move it away first, or use --out")
open(out, "w").write(s)
fmt = lambda v: "-" if v is None else (" ".join(f"{x:.3f}" for x in v) if isinstance(v, (tuple, list)) else f"{v:.3f}")
print(f"wrote {out} | flip {a.flip} wb {fmt(wb)} dmin {fmt(dmin)} dmax {fmt(dmax)} crop {fmt(crop)}")
