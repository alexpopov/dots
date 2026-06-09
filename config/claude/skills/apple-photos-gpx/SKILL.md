---
name: apple-photos-gpx
description: Retroactively edit location, date, or timezone on photos that already live inside macOS Photos.app (and iCloud Photos) — including applying a GPX track. Use when the user wants to geotag, fix a wrong-TZ camera clock, shift timestamps, or apply GPS coordinates to photos that are NOT loose files but are inside Photos.app. Distinct from the `photo-exif` skill, which edits loose JPEG/RAW files before import.
---

# Apple Photos.app + GPX

## When to reach for this skill

The user has photos **already in Photos.app** (typically synced to iCloud Photos) and wants to:
- Apply a GPX track to set GPS on many photos
- Fix a wrong-TZ camera clock (Leica/Fuji/etc. left on a different timezone)
- Shift timestamps by a delta (e.g. camera clock drift)
- Override GPS on a batch of photos to a single named location

If the photos are still loose files (e.g. fresh lab scans not yet imported), use the `photo-exif` skill instead — exiftool is faster and there's no Photos.app round-trip.

## Why exiftool alone won't work here

Photos.app stores metadata in its own SQLite catalog (`Photos.sqlite`) and treats the originals on disk as immutable inputs. Writing EXIF directly to the file inside `~/Pictures/Photos Library.photoslibrary/originals/` does **not** trigger an iCloud re-upload — other devices stay unaware, and Photos.app may even revert the visible metadata on next sync. The only iCloud-safe paths are:

1. Photos framework (`PHAssetChangeRequest`) — what GeoTag.app and Houdah call into
2. AppleScript / `osxphotos` driving Photos.app — same underlying mechanism

Both edit the catalog; CloudKit then propagates the change.

## Primary tool: `osxphotos`

Install persistently: `uv tool install osxphotos` (puts `osxphotos` on `$PATH` at `~/.local/bin/osxphotos`). The helpers in this skill assume this is installed — they call `osxphotos` directly, not `uvx`. The `uvx` fallback is in the per-command snippets below for one-offs.

**Sandbox note:** if Claude is in a permission-restricted shell and uv can't write to `~/.cache/uv` or `/tmp`, set `UV_CACHE_DIR=~/dots/.uv-cache-tmp` (or another writable path) before any `uvx` command. Persistent-install (`uv tool install`) avoids the cache issue entirely for routine use.

**Crash log note:** osxphotos drops `osxphotos_crash.log` into `$CWD` on errors. If the CWD is in iCloud Drive, that file syncs everywhere. Run from a non-iCloud dir, or `rm` the log after.

## Helper scripts (reach for these first)

Two scripts live in this skill dir. Both default `UV_CACHE_DIR` to `~/dots/.uv-cache-tmp` (writable inside Claude's sandbox).

- **`show-selected.sh`** — terse table of currently-selected photos: file, date+offset, TZ name, GPS. Always run this first to diagnose what Photos.app actually has.
- **`tz-fix.sh CAMERA_TZ ACTUAL_TZ`** — the canonical two-step timewarp. Prints before-state, applies, prints after-state. Cleans up `osxphotos_crash.log` from `$CWD` afterwards.
- **`set-location.sh (--gps LAT,LON | --location KEY)`** — apply GPS to the current selection. Coordinates inline, or a named preset from `locations.local.json` (gitignored, mirrors the `photo-exif` skill convention).
- **`gpx-match.sh GPX_PATH [--pre-fallback first|skip] [--overwrite] [--dry-run]`** — match each selected photo to the nearest GPX trackpoint and apply. Uses `osxphotos run` + the `photoscript` library in a single process — ~200ms/photo vs ~1min/batch-edit-invocation. Reach for this whenever GeoTag fails or you want it scripted. Default skips photos that already have GPS; `--overwrite` to redo. `--pre-fallback first` tags pre-GPX photos with the first trackpoint (useful when tracking started mid-day).

Examples:
```bash
~/dots/config/claude/skills/apple-photos-gpx/show-selected.sh

# Camera was on Zurich; user was in Tokyo
~/dots/config/claude/skills/apple-photos-gpx/tz-fix.sh Europe/Zurich Asia/Tokyo

# Camera was on Zurich and user was also in Zurich — collapses to single
# "relabel as Zurich with match-time" pass. Wall clock stays put, UTC corrects.
~/dots/config/claude/skills/apple-photos-gpx/tz-fix.sh Europe/Zurich Europe/Zurich

# GPS for the selection
~/dots/config/claude/skills/apple-photos-gpx/set-location.sh --gps "47.4617142,8.5508599"
~/dots/config/claude/skills/apple-photos-gpx/set-location.sh --location home
```

Use the raw osxphotos commands below only when the canonical pattern doesn't fit (clock drift, single TZ relabel, GPS-only edits, etc.).

## Sandbox/stdin gotchas

- **`osxphotos timewarp`** prompts y/N; pass `--force --plain` to bypass and use plain output.
- **`osxphotos batch-edit`** has no `--force`. It blocks on stdin EOF in non-TTY environments, hanging forever at "Processing N photos...". Fix: redirect stdin with `</dev/null`. The helpers handle this — only matters if invoking osxphotos directly.
- **`uvx`** can't write to `~/.cache/uv` or `/tmp` inside Claude's sandbox. The helpers default `UV_CACHE_DIR` to `~/dots/.uv-cache-tmp` (writable). Override by exporting `UV_CACHE_DIR` before invoking.
- **`osxphotos` crash log** ends up in `$CWD/osxphotos_crash.log`. If CWD is in iCloud Drive, the file syncs everywhere — annoying. Helpers clean it up; if invoking directly, run from a non-iCloud dir.

## Querying selected photos manually

If `show-selected.sh` won't fit (need different fields, JSON for further processing):

```bash
UV_CACHE_DIR=~/dots/.uv-cache-tmp uvx --quiet osxphotos query --selected --json \
  | jq -r '.[] | "\(.original_filename)  \(.date)  tz=\(.tzname)  utc_offset=\(.tzoffset)"'
```

Key fields: `date` (ISO with offset), `tzname` (IANA), `tzoffset` (seconds), `latitude` / `longitude`.

## `timewarp` — fixing time and timezone

`osxphotos timewarp` operates on the currently-selected photos in Photos.app by default (no `--selected` flag — `timewarp` will reject it). Always pass `--force --plain` in scripted use:

```bash
UV_CACHE_DIR=~/dots/.uv-cache-tmp uvx --quiet osxphotos timewarp \
  <FLAGS> --force --plain
```

### Semantics — read carefully, these are easy to flip

| Flag | UTC instant | Wall clock | TZ label |
|---|---|---|---|
| `--timezone X` | unchanged | shifts to match new TZ | becomes X |
| `--timezone X --match-time` | shifts | unchanged | becomes X |
| `--time-delta "+Nh"` | shifts by +N | shifts by +N (in current TZ) | unchanged |
| `--date YYYY-MM-DD` | sets date portion of wall clock | sets date | unchanged |
| `--time HH:MM:SS` | sets time portion of wall clock | sets time | unchanged |

`--inspect` prints current state — it is **not** a dry-run preview of the change.

### Common patterns

**Camera was on the wrong timezone (clock instant wrong)** — e.g. Leica left on Zurich CET while shooting in Hong Kong (HKT). The wall clock the camera recorded ("00:52") was the camera's TZ, but Photos.app guessed JST or HKT and mis-stored the UTC instant.

Two-step fix:
```bash
# Step 1: tell Photos the wall clock IS the camera's old TZ. --match-time keeps the
# wall clock and corrects the UTC.
osxphotos timewarp --timezone Europe/Zurich --match-time --force --plain

# Step 2: relabel to the TZ where the user actually was. No --match-time → UTC stays,
# wall clock shifts.
osxphotos timewarp --timezone Asia/Hong_Kong --force --plain
```

After step 1 + 2, a photo recorded as "00:52 Zurich" displays as "07:52 Hong Kong" (same UTC moment), and Photos.app shows it in the user's local TZ correctly.

**Clock drift (e.g. camera was 7 minutes fast)**:
```bash
osxphotos timewarp --time-delta "-00:07:00" --force --plain
```

**Photo TZ label is wrong but instant is right**:
```bash
osxphotos timewarp --timezone Asia/Tokyo --force --plain
```

**Reset to original** (macOS 13+):
```bash
osxphotos timewarp --reset --force --plain
```

## Applying GPX tracks

Two routes, depending on track size and user preference:

**Recommendation:** use `gpx-match.sh` (the library-API path) — it's faster than GeoTag *and* scriptable. The old `batch-edit`-per-group approach is what's slow (~1 minute per group). Avoid it for multi-point GPX matching; use it only for single-location batches via `set-location.sh`.

### Route A — GeoTag.app (recommended, GUI)

[GeoTag](https://www.snafu.org/GeoTag/) by Marco Hyman. Free, MIT-source, very active. The same author writes the iOS "Geotag Photos" app that produces these GPX files. Install: `brew install --cask geotag` or Mac App Store.

**The interface is non-obvious. Memorize these:**

- **No Photos sidebar exists.** The only way to load Photos-Library items is the toolbar **photo icon** (top-right). On first launch you must click it **twice** — once to trigger the system permission prompt, again to open the picker. Documented behavior, not a bug.
- **A backup folder must be configured even though Photos-Library items aren't backed up.** If unset, ⌘S is greyed out forever. Settings (⌘,) → pick a folder, or check **Disable Image Backups**.
- **Loading a GPX does not auto-match.** You have to ⌘A (select all rows) → ⌘L (Edit → Locn from Track). Without ⌘L, dropping the GPX just draws the track on the map and does nothing else.
- **GeoTag resets the timezone to system default on every launch.** Edit → Specify Time Zone… → pick shoot location → Change. Re-do ⌘L after the change. If pins all land on one endpoint or don't appear, this is usually why.
- **Time-shift tolerance** lives in Settings → **Extend track timestamps** (default 120 min). Raise it if photos fall just outside the GPX window.

Click path for the canonical "Photos selected, GPX in hand" case:

1. `open -a GeoTag`
2. Toolbar photo icon → picker → select photos → **Add**
3. Drag the `.gpx` onto the table (or File → Open ⌘O)
4. ⌘A → ⌘L. Green lat/long = matched unsaved change
5. Spot-check pins on the map. Move a pin = single click on the new spot (don't drag). Delete a match = select rows + Delete
6. ⌘S — writes via PhotoKit → iCloud syncs

RAW+JPEG pairs: Settings → **Disable paired jpegs** controls whether the JPEG side gets the same edit. Fixed in 5.7. Not relevant for JPEG-only lab scans.

### Route B — `osxphotos batch-edit --location` (CLI)

Use the `set-location.sh` helper. Best fit: a single location for many photos (HKG airport, home, a venue). Filter by UUID list via `--uuid-from-file <file>` to scope without changing the Photos.app selection.

**GPX time-matching via osxphotos** is possible but slow (each `batch-edit` group is ~1 min of overhead). Pattern, if you must do it programmatically:
1. Parse GPX → list of `(epoch_utc, lat, lon)`.
2. Query selection JSON, split pre-GPX vs in-range.
3. Group photos by their nearest GPX point.
4. Write each group's UUIDs to a temp file.
5. One `batch-edit --uuid-from-file <file> --location LAT LON` per group.

For Route B's "all-in-one" GPX case, prefer GeoTag — fewer subprocess spawns, interactive review.

## Decoding Google Maps URLs for location coords

If the user gives a Google Maps share link, follow the redirect and grab `!3d!4d` (pin coords, more precise than the `@` map-center coords):

```bash
curl -sIL "<maps-url>" | grep -i '^location:'
```

Same trick as in the `photo-exif` skill — see there for fuller notes.

## GPX file notes

- The Tokyo example was generated by **Geotag Photos** (iOS app), prefix `<gpx creator="Geotag Photos ...">`. UTC timestamps with a `<!-- TZ: <offset-seconds> -->` comment hint.
- File name reflects the day the file was *created*, not the time range — always inspect actual timestamps with:
  ```bash
  python3 -c "import re; t=re.findall(r'<time>([^<]+)', open('FILE').read()); print(f'{t[0]} → {t[-1]} ({len(t)} pts)')"
  ```

## Workflow checklist

1. Identify which photos the user has selected (`osxphotos query --selected --json`)
2. Check whether their timestamps fall inside the GPX time range — if not, the GPX won't geotag them
3. If TZ/clock looks wrong, fix it with `timewarp` BEFORE geotagging — GPS matching is by UTC instant, so a wrong TZ breaks the match
4. Apply GPS via GeoTag (interactive, time-matched) or `osxphotos batch-edit --location` (single coord)
5. After save, suggest user check sync on iPhone (Photos.app → photo → Info → Location)

## Things that go wrong

- **Crash on TTY-less invocation**: `timewarp` prompts y/N by default. Always pass `--force --plain`.
- **`--selected` rejected**: `timewarp` infers selection automatically. The flag is only valid on `query` and `batch-edit`.
- **iCloud "Optimize Mac Storage"**: catalog edits (location, date) succeed even on placeholder assets — they don't require the original. EXIF rewrites (`--push-exif`) do require it.
- **Live Photos**: writing location may only update the still side, not the paired video. Verify on iPhone after.
- **Multiple TZ guesses**: Photos.app sometimes assigns TZ based on the *next* photo in the import batch. If a user shot across timezones in one trip, expect inconsistent `tzname` across the set — fix as a group with `timewarp` after.
