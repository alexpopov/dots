"""gpx-match.py — match currently-selected Photos.app items to a GPX track and
apply the nearest trackpoint's coords. Uses osxphotos/photoscript library API
in a single process — avoids the ~1 min/invocation overhead of `batch-edit`.

Run with:
    osxphotos run gpx-match.py PATH_TO_GPX [--pre-fallback first|skip]
                                            [--overwrite]
                                            [--dry-run]
"""
import argparse
import re
import sys
from bisect import bisect_left
from datetime import datetime

from photoscript import PhotosLibrary


def parse_gpx(path):
    text = open(path).read()
    pts = []
    for m in re.finditer(
        r'<trkpt lat="([^"]+)" lon="([^"]+)"[^>]*>.*?<time>([^<]+)</time>',
        text,
        re.DOTALL,
    ):
        ts = datetime.fromisoformat(m.group(3).replace("Z", "+00:00")).timestamp()
        pts.append((ts, float(m.group(1)), float(m.group(2))))
    return sorted(pts)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("gpx", help="path to GPX file")
    ap.add_argument(
        "--pre-fallback",
        choices=["first", "skip"],
        default="skip",
        help="for photos before the first GPX point: 'first' = use first trackpoint, 'skip' = leave alone",
    )
    ap.add_argument(
        "--overwrite",
        action="store_true",
        help="re-tag even photos that already have GPS (default: skip them)",
    )
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    pts = parse_gpx(args.gpx)
    if not pts:
        sys.exit("No trackpoints found")
    times = [p[0] for p in pts]
    print(
        f"GPX: {len(pts)} pts, {datetime.fromtimestamp(times[0])} → {datetime.fromtimestamp(times[-1])}"
    )

    lib = PhotosLibrary()
    sel = lib.selection
    print(f"Selected: {len(sel)} photos\n")

    n_set = n_skip_has_gps = n_skip_before = n_no_date = 0
    for photo in sel:
        if photo.location and photo.location != (None, None) and not args.overwrite:
            print(f"  {photo.filename}: skip (already has GPS)")
            n_skip_has_gps += 1
            continue
        if not photo.date:
            print(f"  {photo.filename}: skip (no date)")
            n_no_date += 1
            continue
        pt_time = photo.date.timestamp()
        if pt_time < times[0]:
            if args.pre_fallback == "skip":
                print(f"  {photo.filename}: skip (before GPX start)")
                n_skip_before += 1
                continue
            chosen = pts[0]
            delta = times[0] - pt_time
            note = "first-point fallback"
        else:
            i = bisect_left(times, pt_time)
            cands = ([pts[i - 1]] if i > 0 else []) + ([pts[i]] if i < len(pts) else [])
            chosen = min(cands, key=lambda x: abs(x[0] - pt_time))
            delta = abs(chosen[0] - pt_time)
            note = f"Δ={delta/60:.1f}min"
        lat, lon = chosen[1], chosen[2]
        prefix = "[dry] " if args.dry_run else ""
        print(f"  {prefix}{photo.filename}: → ({lat:.6f}, {lon:.6f})  {note}")
        if not args.dry_run:
            photo.location = (lat, lon)
        n_set += 1

    print(
        f"\n{n_set} set, {n_skip_has_gps} skipped (had GPS), "
        f"{n_skip_before} skipped (pre-GPX), {n_no_date} no date"
    )


if __name__ == "__main__":
    main()
