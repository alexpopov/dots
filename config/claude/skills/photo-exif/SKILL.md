---
name: photo-exif
description: Backfill EXIF on Alp's film-scan JPEGs — camera, lens, sequenced DateTimeOriginal, and GPS — so they sort and identify correctly when imported into Photos.app. Use when the user wants to set/fix camera, lens, date, or location on a folder of images (typically under `~/Library/Mobile Documents/com~apple~CloudDocs/Pictures/To Import/`).
---

# Photo EXIF backfill

Alp shoots film, sends rolls to a lab, and receives JPEGs scanned by a Noritsu Koki HS-1800. The scanner writes its *own* identity into EXIF (`Make=NORITSU KOKI`, `Model=EZ Controller`) and leaves `DateTimeOriginal` / `CreateDate` empty. Before these import into Photos.app cleanly, EXIF needs backfilling.

## The script

`set-exif.sh` wraps exiftool with three batched concerns:

1. **Camera + lens** — looked up by key from `cameras.json`
2. **Sequenced date** — base `DateTimeOriginal` plus N-second increments so Photos.app preserves frame order
3. **GPS** — decimal coords

Example:
```bash
~/dots/config/claude/skills/photo-exif/set-exif.sh \
  --camera canon-7 --lens canon-50-1.8 \
  --date "2025-07-06 12:00:00" --step 1 --tz "+02:00" \
  --gps "47.2913799,8.5277585" \
  /path/to/000071040001.jpg /path/to/000071040002.jpg ...
```

Always pass files in the order they should sort. For lab scans the filename order is already the frame order, so a shell glob works:
```bash
set-exif.sh ... "$DIR"/000071040{0001..0024}.jpg
```

**Default to `--no-backup`.** Alp doesn't want `<file>_original` files cluttering the scan dirs. Omit it only if there's specific reason to keep a backup for that run. To clean up backups left by an earlier run, move them to `/tmp/` (don't delete outright — Alp prefers a recoverable step).

Use `--dry-run` to preview the exiftool commands before running.

## Private location presets (`locations.local.json`)

For locations that shouldn't be in the public repo (home, friends' places, etc.), use `--location KEY` instead of `--gps`. The script reads `locations.local.json` from the skill dir; that filename is gitignored (`config/claude/skills/photo-exif/*.local.json`).

Schema:
```json
{
  "locations": {
    "home": { "description": "Home", "lat": "47.xxx", "lon": "8.xxx" }
  }
}
```

When the user names a private location, add it to `locations.local.json` (which already exists if they've used the feature before). Do not put private coords in `cameras.json`, the SKILL.md, or anywhere else under version control — that includes commit messages and PR descriptions.

## Presets (`cameras.json`)

Two flat dictionaries: `cameras` and `lenses`, keyed by short slugs. Each entry has a human `description` and an `exif` map that becomes `-Tag=Value` args.

When the user mentions a camera or lens that isn't in `cameras.json` yet, add it:
- Camera: at minimum `Make`, `Model`.
- Lens: `LensMake`, `LensModel`, `FocalLength`, `FocalLengthIn35mmFormat`, `MaxApertureValue` (lens's widest aperture — not per-shot FNumber, which we don't know for film).

Confirm the slug and description with the user before saving the preset.

## Resolving locations

The user can give a location in any form — proceed without asking them to convert:

- **Google Maps share URL or short link** (`maps.app.goo.gl/...`, `google.com/maps/...`, `goo.gl/maps/...`): follow the redirect and pull coords out of the resolved URL:
  ```bash
  curl -sIL "<url>" | grep -i '^location:'
  ```
  The resolved URL has both `@LAT,LON,ZOOMz` (map-view center) and `!3dLAT!4dLON` (the actual pin). **Prefer `!3d!4d`** — for pinned places those can differ from `@` by 100m+. If only `@` is present (a "dropped pin" with no place data), use that.
- **Place name** (e.g. "Wildnispark Langenberg, Zürich"): the user expects you to figure it out. Ask only if genuinely ambiguous.
- **Decimal coords** (e.g. `47.38, 8.54`): use directly with `--gps`.

For private locations, save under a key in `locations.local.json` instead of passing `--gps` (see above).

## Workflow checklist

1. Read the source directory and current EXIF on one file (`exiftool <file>`) — confirm what's missing.
2. Gather from the user: camera, lens, date(s), location. If they give a range of files belonging to one shoot, note where the next shoot starts.
3. If a new camera/lens, add to `cameras.json` and confirm slug.
4. Run with `--dry-run` first if anything's uncertain.
5. Apply.
6. Re-read EXIF on one file to verify (`exiftool -DateTimeOriginal -Model -LensModel -GPSPosition <file>`).

## Exporting to HEIC for Photos.app import

Lab/home TIF scans are 100+ MB each (16-bit, uncompressed). For Photos.app import they should be downscaled + compressed first so the iCloud Photos library doesn't bloat. The canonical workflow:

1. **Tag the TIFs** (this skill) — date, camera, lens, GPS, film stock. The TIFs are the canonical archive; keep them in iCloud Drive (`~/Library/Mobile Documents/com~apple~CloudDocs/Pictures/Imported/...`).
2. **Convert to HEIC** with `tif-to-heic.sh` — defaults to 3840 long-edge max, q=80, output to a separate dir (typically `~/Desktop/Scans/...` or similar).
3. **Import the HEICs** into Photos.app (`open -a Photos <dir>/*.heic`).

### Why a wrapper script

`sips` is fast (hardware HEIC encode on Apple Silicon) and preserves most EXIF — *except* `Keywords` and XMP `Subject` are silently dropped during TIF→HEIC. So film-stock tags vanish unless you re-copy them. `tif-to-heic.sh` does the sips encode then runs `exiftool -tagsfromfile` to put Keywords/Subject back.

### Usage

```bash
~/dots/config/claude/skills/photo-exif/tif-to-heic.sh \
  --out "$HOME/Desktop/Scans/Canon 7/Porta 1" \
  "/Users/alp/Library/Mobile Documents/com~apple~CloudDocs/Pictures/Imported/Canon 7/Porta 1"/*.tif
```

Defaults: 3840 max long edge, quality 80, 8 parallel workers. For 34 frames expect ~50–60 seconds and ~50 MB output.

Quality reference (from earlier benchmarks on a 5034×3437, 108 MB TIF):
- q=95 @ 3840: ~5.5 MB (19× compression, indistinguishable at viewing size)
- q=80 @ 3840: ~1.5 MB (75× compression, fine for tag/sort, mild grain softening if you pixel-peep)

## Timezones

`DateTimeOriginal` is a wall-clock string with no zone. Photos.app uses the file's location to infer the zone, but setting `OffsetTimeOriginal` explicitly avoids surprises. Common values for Alp:
- Zürich summer (CEST): `+02:00`
- Zürich winter (CET): `+01:00`
