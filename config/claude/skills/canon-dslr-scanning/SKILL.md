---
name: canon-dslr-scanning
description: DSLR-scan film negatives with the Canon R5 Mark II tethered to the M2 Mac through EOS Utility 3, then invert in darktable, export TIFFs for Darkroom, archive CR3 + xmp + exif.json, and fix dust. Use when the user wants to scan/digitize negatives with the camera, tether the R5, mentions EOS Utility (freezing, not detecting, beachballing), darktable inversion or re-export of scans, or dust on scanned negatives.
---

# Canon DSLR scanning (R5 Mark II → darktable)

Alp digitizes negatives with a **Canon EOS R5 Mark II** (EU3 window title "EOS R5m2") tethered over USB-C to the M2 Mac with **EOS Utility 3** (`/Applications/Canon Utilities/EOS Utility/`). Captures are CR3s, inverted in darktable, exported as 16-bit TIFFs, tagged with the `photo-exif` skill, then edited in Darkroom or imported into Photos.

**dots rule: never kill a process without Alp's explicit go.** Every `pkill`/`kill` below is something to propose, not run.

## 1. Pre-flight (run before every session, read-only)

```bash
pgrep -lx ptpcamerad || echo "ptpcamerad not running"            # should be not running
launchctl print-disabled gui/501 | grep ptpcamerad                # should say disabled
pgrep -lx 'Photos|Preview|Image Capture' || echo "none"           # should be none
pgrep -lf 'EOS Utility'                                           # EU3 state
pgrep -lf 'log show --info --last 48h' || echo "no stuck log show"
ioreg -p IOUSB -l -w 0 | grep -i canon                            # camera enumerated?
sysctl vm.swapusage                                               # thrashing → beachballs
```

Use `ioreg`, not `system_profiler SPUSBDataType` (empty on Apple Silicon). If the camera shows in ioreg, cable and port are fine. In ioreg, "Device Speed" 4 = USB 3, 2 = USB 2. Chrome appearing as an `AppleUSBHostDeviceUserClient` on the camera is harmless.

Then: plug in, power on, and launch the real app:
```bash
open "/Applications/Canon Utilities/EOS Utility/EU3/EOS Utility 3.app"
```
**Do not launch `EOS Utility/EOS Utility.app`.** That is Canon's windowless background launcher (process name `EOS Utility`, often running for days). Opening it shows nothing, and seeing it in `pgrep` does not mean the app is up. The app the user sees is process `EOS Utility 3`; check for it with `pgrep -lf 'EOS Utility 3'`. This mix-up cost several rounds on 2026-11-19 to 22.

When checking state, take one fresh reading of both facts together and report exactly that: `pgrep -lf 'EOS Utility 3'` and `ioreg -p IOUSB -w 0 | grep -ic canon` (the device is named "Canon Digital Camera"). Both change within seconds as the camera is cycled or EU3 exits, so never reuse a reading from an earlier command. On 2026-11-22 EU3 was up and connected at a moment I reported it as not running.

EU3 also quits itself after freezing (2026-11-22 16:59, Alp did not quit it): the unified log shows an ordinary AppKit `terminate:` sequence (`applicationShouldTerminate` cancelled once, then approved), no crash or hang report, and no camera or USB lines at all, because Canon's SDK does not log there. Photos and `ptpcamerad` were closed and 35 % of memory was free, so neither contention nor memory explains it. Do not read a clean terminate sequence as "the user quit". To get evidence, start EU3 with USB logging (`LIBUSB_DEBUG=4 nohup ".../EU3/EOS Utility 3.app/Contents/MacOS/EOS Utility 3" > log 2>&1 &`) and, while it is frozen and before it exits, run `sample <pid> 5` to capture what it is blocked on.

First USB capture of a freeze (2026-11-22, EU3 3.21.11, live view open): live view streams about 6.5 MB/s continuously; each shot adds a 40-50 MB burst. About 10 s after the second shot finished downloading, EU3 sent a command and the camera never answered: one bulk read timed out after exactly 30 s (`transfer error: timed out`, actual_length=0), then EU3 released the interface and quit. No stall, no device-removed error. So the 30 s "not responding" is EU3 blocked on a silent camera, and the cause is on the camera or link side, not macOS contention or memory. Analysis recipe: sum `sync_transfer_cb actual_length` per 5 s window; find the last transfer before the timeout. The debug log grows about 1 MB/s with live view on.

EU3 exits quietly: launchd logs `service inactive` for `com.canon.EOS-Utility-3` with no crash report (seen twice on 2026-11-22, each after a few minutes, with swap nearly full). The frame being shot at that moment does not reach the Mac; it may be on the card.

Confirm the connection by window title (the ioreg `IOUserClientCreator` count does NOT show EU3's connection):
```bash
osascript -e 'tell application "System Events" to tell process "EOS Utility 3" to get name of windows'
```
Main window titled "EOS R5m2" = camera connected (EU3 does not open live view by itself; the user clicks **Remote Shooting**, the main window's buttons have no accessibility names, so don't click blind). "Remote Live View window" = live view running.

## 2. Capture settings

**ALWAYS remind Alp: the first shot after EU3 connects never saves to the Mac.** The file just doesn't arrive (e.g. 2026-11-19: IMG_0001 missing, folder starts at IMG_0002). Fire a throwaway frame first (lens cap on is fine), then start the real sequence. It may still be on the card if the destination includes it. Don't let the bare-light reference or frame 1 of a sheet be that first shot.

Baseline (from Alp's scan CR3s, Nov 2026): **ISO 200, f/4, 1/30 s, WB manual 5500 K**, manual exposure, drive mode **2-second self-timer** (no shake from the press). Lens is adapted/manual (EXIF LensModel blank). To re-check, read the newest local CR3s only; don't `find` the iCloud RAWs archive, it's too slow (files may be cloud-only):
```bash
ls -t ~/Pictures/*/*.CR3 | head -3 | tr '\n' '\0' | xargs -0 exiftool -q -T -FileName -ISO -FNumber -ExposureTime -WhiteBalance -ColorTempAsShot
```
**Once-over of a whole session:** `check-scans.py <folder or files>` (in this skill folder; runs via `uv`) prints OK or NAY per CR3 from the raw data, with the fix (stops to add, or shorten the shutter) and the location of any clipped pixels. `check-scans.py --watch [DIR]` stays running and judges each new file as it lands (bell on NAY); suggest Alp run it in a tmux split during a session so no tokens are spent on checking. With the black mask (no bare pad in frame), aim for the brightest channel at 70-95 % of full scale: on 2026-11-22 a 4x5 Fomapan sheet needed ISO 200, f/4, **1/8 s** (green 90 %); 1/15 s left it at 44 %. Brighter is cleaner right up to clipping, since the sensor is linear.

**Checking a capture's exposure** (each step takes a few seconds; if one takes longer, something is wrong):
```bash
dcraw_emu -4 -T -Z /tmp/x.tiff IMG_xxxx.CR3        # linear 16-bit (no -D in this build)
magick /tmp/x.tiff -sample 25% /tmp/xs.tiff
"/Users/alp/Desktop/Export Pile/image-info.sh" /tmp/xs.tiff   # print-image-check's script; values are LINEAR here
```
For stops: `magick … rgb:` raw dumps are little-endian (`<u2` in numpy). Reading them as `>u2` gives nonsense "clipping". The bare light pad around the sheet is the brightest thing in frame; expose so its brightest channel (red) is ≈ 85–95% (white level 13535, black 512). 2026-11-19 at 1/30: pad red max 58% → use 1/20 (1/15 clips red); densest film ≈ 7 stops below pad (D≈2.1).

Sanity-check regions before trusting numbers: render `magick xs.tiff -evaluate pow 0.4545 -resize 800x view.png` and look, plus a coarse grid (`-colorspace gray -resize 10x6! txt:-`). The pad was uneven that day (left 42%, right 33%, ≈0.4 EV), so for density comparisons across a sheet shoot a **bare-pad flat-field frame** at identical settings and divide by it.

For density comparisons, shoot a bare-light frame (no film) first, shorten the shutter until it doesn't clip, then keep every setting fixed for all frames.

- Destination: **"Computer and camera memory card"**. EU3 drops connections and loses the last frame; the card is the backup. Fallback workflow: shoot to card, import via a card reader.
- Save folder: `~/Pictures/<shooting date>/` (`defaults read com.canon.EOS-Utility-3` → `kEOSSaveFolderPath`).
- Check the camera clock. It was once still on Pacific time and frames landed in the previous day's folder.

## 3. EOS Utility troubleshooting

**Why it breaks:** the R5 allows only ONE PTP host session. macOS `ptpcamerad` (Image Capture, Photos, Preview's "Import from Camera") contends for it.

**Durable fix (in place since 2026-10-05):** `launchctl disable gui/501/com.apple.ptpcamerad`, then `kill -9` the running copy (plain kill is ignored; `bootout` fails under SIP). The flag persists. Undo when Alp wants iPhone/camera imports in Photos: `launchctl enable gui/501/com.apple.ptpcamerad`. A copy started before the disable can live on for weeks and still log `CM | add:` for Photos/Preview; it exited by itself once both apps were quit.

**Symptom → cause → fix:**

| Symptom | Cause | Fix |
|---|---|---|
| Beachball on launch, 0% CPU | Canon pipe deadlock: EU3 runs `log show --last 48h --predicate 'process == "ptpcamerad" AND eventMessage contains "CM \| add:"'` into a pipe and waits before reading. >64 KB output blocks forever. Recurs every launch until those lines age out of 48 h. | `pkill -f 'log show --info --last 48h'`; quit whatever keeps registering as an Image Capture client |
| EU3 refuses to connect | Any app named in those 48 h log lines is still alive (Photos, Preview) | Quit them. Find culprits: `log show --last 10m --predicate 'process == "ptpcamerad"'` → `CM \| add: [<pid>]` |
| Works briefly, freezes, never re-detects | Stale PTP session after crash/force-quit | `pkill -f 'EOS Utility'`; `sudo pkill -f ptpcamerad` (confirm PID changed, it can survive); power-cycle camera; relaunch |
| Power switch does nothing, session survives power cycles (same ioreg `sessionID`) | **Frozen camera firmware** | Unplug USB + pull battery. Check the camera responds to its own buttons before blaming macOS |
| Beachball with no stuck `log show` | Mac thrashing (swap near full, jetsam idle-exits) | Check `sysctl vm.swapusage`; close memory hogs or reboot |
| Connection drops, EU3 window reappears | Not a crash: launchd logs `exited due to exit(0)`, launcher respawns `EOS Utility 3`. Changed ioreg `sessionID` = camera re-enumerated | `log show --last 10m --predicate 'process == "launchd" AND eventMessage contains "EOS-Utility-3"'` |

**Deep diagnosis:** run `".../EOS Utility 3.app/Contents/MacOS/EOS Utility 3"` with `LIBUSB_DEBUG=4`, capture stderr. If open/claim succeed but bulk OUT on ep 0x02 times out every 5 s, the camera isn't responding; it's not a host-side conflict.

## 4. darktable

### Export for Darkroom: uncompressed TIFF

Darkroom can't open darktable's default deflate TIFFs (deflate + predictor + `RowsPerStrip=1`); they fail silently. Set export compression to **uncompressed**, 16-bit (~196 MB at 6548×5236 vs ~159 MB deflate). To fix files already exported:
```bash
magick "$f" -compress none "$out"
exiftool -overwrite_original -TagsFromFile "$f" -all:all "$out"
```
Then `trash` the originals after verifying.

### Reusing an edit on a new folder

Copy a finished `.CR3.xmp` next to each new CR3 before importing. Strip `exif:DateTimeOriginal`, `darktable:import_timestamp`, `darktable:change_timestamp` and `darktable:history_current_hash`, and set `xmpMM:DerivedFrom` to the new file name. darktable applies the sidecar on import.

**B&W negatives: use `bw-negative-template.CR3.xmp`** (in this skill folder) instead of copying an old edit. Copy it next to each CR3 as `<name>.CR3.xmp` and replace `TEMPLATE.CR3` in `xmpMM:DerivedFrom` with the file name. It is the 2026-11-04 negadoctor edit with crop and perspective off, color calibration disabled, and white balance set to the as-shot coefficients (camera at 5500 K manual: R 1.9619, B 1.4736, from EXIF `WB_RGGBLevelsAsShot` / 1024). Edits copied with both white balance and color calibration active show darktable's "white balance module error" on every frame; with only white balance active it cannot occur. Tested 2026-11-19: film area stays near neutral. Disabling color calibration without resetting white balance turns the image blue. Keep color calibration for colour negatives. Since 2026-11-23 the template also has the exposure module at 0 EV / black 0 (darktable auto-applies +0.7 EV and black -0.0002 to every raw; Alp wants the scan untouched) and negadoctor's scan exposure bias at 0 (darktable's default is -0.05), and `make-bw-sidecar.py` writes D min as the measured film base with no gain. It also carries a disabled retouch (no shapes) and a disabled rgb curve (straight line) as the last two history entries, so both are ready to switch on. Older sidecars carry +0.7 EV with D min 1.62x higher, sometimes clamped at the slider's 1.5 limit; to convert one, zero exposure and divide D min by 2^0.7. Orientation and negadoctor Dmax still need setting per frame, and darktable rewrites the sidecar once the folder is imported, so don't edit sidecars while it is open.

negadoctor's print tab caps the whites. Output = soft-clip((exposure x (1 + black - 10^x))^grade). darktable's defaults (print exposure -0.11 EV, paper black +7.55 %) are a matched pair that puts paper white just under 1.0, so changing them barely moves the top; the cap comes from **paper gloss** at 75 %, which rolls off everything above 0.75 and limits output to about 90 %. Every export on 2026-11-19 to 22 peaked at 83-90 % for this reason. Raise paper gloss toward 100 % for whites that reach white. Since 2026-11-22 the template uses print exposure 0 EV and paper black 0 % (Alp's preference: slightly deeper blacks and midtones); gloss is still 75 %.

**Blue (or tinted) blacks in a B&W inversion = white balance not neutral on the film base.** negadoctor in black-and-white mode uses one D min for all three channels, and paper grade 4 amplifies any channel mismatch in the shadows: on 2026-11-22 a 4 % error in the blue multiplier (1.418 instead of 1.480) made the blacks render as RGB 3/6/25 instead of neutral, and saturation -100 % in color balance rgb did not remove it. **Global chroma -100 % in the same module does** (Alp found this), as does the monochrome module or the 'contrast brightness saturation' module at the end of the pipeline; `--mono` now sets global chroma too. So a neutral result no longer depends on perfect white balance, though a mismatch still shifts tonality. Always pass `--wb` measured from the film itself (raw G/R and G/B of a thin area, via rawpy), not the camera's as-shot values; Fomapan 100 on the pad measured R 1.870, B 1.480. In the GUI: white balance module, channel coefficients. When checking a render for neutrality, compare R, G and B separately; a grey conversion hides this.

`make-bw-sidecar.py FILE.CR3 --auto --flip N --mono [--out PATH]` (in this skill folder; runs via `uv`) measures the scan and writes a sidecar with white balance from the film base, D min, D max and a crop to the sheet (needs the black mask; `--inset` trims the rebate, default 3 %). `--help` lists the manual overrides. Orientation: sheets scanned emulsion side up come out mirrored; flip code 2 = mirror only (landscape), 7 = quarter turn + mirror (portrait). Confirm mirroring from lettering in a frame, and check a small contact sheet before applying. Workflow used on 2026-11-22 for 12 Fomapan sheets: generate with `--out` into a scratch folder, launch darktable into the lighttable, `apply_sidecar` one image per call, then force the sidecar sync. For tinted bases such as blue X-ray film, pass `--wb` with the raw G/R and G/B of the film (read with rawpy via `uv run --with rawpy --with numpy`; 2026-11-20 X-ray sheet: 2.30 1.28) plus `--mono`. Starting D max: ~1.5 for a normal or double-sided negative, ~0.85 for an X-ray sheet with one side stripped. Verify with a `darktable-cli` test render before handing over.

If the darktable GUI is open, `darktable-cli` fails with "can't acquire database lock". Add `--configdir <scratch dir>`.

### Driving the running darktable (`dt-remote`)

`~/dots/bin/scripts/dt-remote` talks to a running darktable over a private D-Bus session bus (Homebrew `dbus`, socket in `~/.cache/dt-remote/`), using darktable's built-in `Remote.Lua` method. Works with the stock 5.4.1 app. `darktable-mcp` cannot do this: it is a separate headless instance.

- `dt-remote launch [FILE]`: start darktable on the bus. Only a copy started this way is reachable. With FILE it opens straight in the darkroom; this is the safe way to open an image.
- `dt-remote lua '<code>'`: run Lua in the app. Start code with `local dt = require "darktable"`; the global `darktable` is nil here.
- `dt-remote open FILE`: import and show FILE, only if the darkroom is already the active view.

Crash rule (2026-11-20, crash report confirmed): never switch views and call `dt.gui.views.darkroom.display_image()` in the same call, and never `tostring()` its return value unless an image is loaded. With no image loaded it returns an invalid handle, and stringifying it segfaults darktable (`image_tostring`). Lua `pcall` cannot catch that. Return `img.filename`-style fields from known-valid images, or plain strings.

Verified: `dt.database.import(path)`, `dt.gui.current_view().id`, `display_image(img)` inside the darkroom, and reading a module's on/off state with `dt.gui.action('iop/monochrome', 0, 'enable')` (returns 0.0 or 1.0). Also verified (2026-11-22): `img:apply_sidecar(path)` on images in the library replaces their edit history in the running app (confirm with `sqlite3 -readonly ~/.config/darktable/library.db`; the `.xmp` on disk is only rewritten later). This is the way to push a sidecar to an image while darktable is open. To reuse one image's edit on others, copy its sidecar, disable crop, rotate-and-perspective and retouch, keep each target's own orientation, then apply. **Deadlock rule (2026-11-22, sampled):** never call `img:apply_sidecar()` on the image that is open (or was last open) in the darkroom. It reloads the develop history while still holding that image's cache lock, and the Lua thread spins forever in `dt_cache_get_with_caller` (stack: apply_sidecar > dt_history_load_and_apply > dt_dev_reload_history_items > colorin reload_defaults > dt_image_cache_get). The GUI keeps running but every later Lua call times out and darktable must be restarted. Apply sidecars only from the lighttable right after a fresh launch, one image per call, and check the library after each. Also give `gdbus` a long `--timeout`; the default 25 s expires on slow calls that are still running.

Do not run a dozen `darktable-cli` renders while the user is working in the GUI: it starves the app and every thumbnail shows "working...".

The `.xmp` on disk can lag far behind the library (2026-11-22: a 5-entry sidecar while the library held 79). Before archiving sidecars from a running darktable, force a write with `img.notes = img.notes or ''` (any metadata setter calls the sidecar sync) and check `history_end` in the file. Untested: changing anything through `dt.gui.action` (toggling modules, moving sliders).

## 5. Tagging and archiving (without keeping the TIFs)

Tag the exported TIF with the **`photo-exif`** skill (camera, lens, date, GPS of the *film* camera). **Never write EXIF onto the CR3s**: darktable picks its raw decoder and colour matrix from Make/Model.

Import the tagged TIF into Photos, then the TIF can go. Archive these three in `iCloud Drive/Pictures/RAWs/<year>/<Month>/<session>/`:

- `IMG_xxxx.CR3`: the digitizing capture
- `IMG_xxxx.CR3.xmp`: darktable edit history (inversion etc.)
- `IMG_xxxx.CR3.exif.json`: the film-camera tags

Dump the tags (after tagging the TIF):
```bash
TAGS='-IFD0:Make -IFD0:Model -IFD0:ImageDescription -ExifIFD:all -GPS:all -IPTC:all -XMP-exif:all -XMP-dc:all -XMP-xmpMM:DerivedFrom'
exiftool -json -G1 -b $TAGS IMG_xxxx.tif | sed 's|"SourceFile": "[^"]*"|"SourceFile": "*"|' > IMG_xxxx.CR3.exif.json
```
(The `SourceFile: "*"` rewrite lets `-json=` apply the dump to any target filename.)

Regenerate the TIF:
```bash
/Applications/darktable.app/Contents/MacOS/darktable-cli IMG_xxxx.CR3 IMG_xxxx.CR3.xmp out.tif \
  --core --library :memory: --conf plugins/imageio/format/tiff/bpp=16 --conf plugins/imageio/format/tiff/compress=0
exiftool -overwrite_original -json=IMG_xxxx.CR3.exif.json out.tif
```
Verified 2026-10-05 on 2026_06_21/IMG_0001: 0 differing pixels against the original export; tags identical apart from IPTC entry order.

**Re-editing an archived frame** (e.g. healing dust): copy its CR3 and `.xmp` out of iCloud into a working folder and import from there. Don't edit inside the archive. After the user exports, apply the archived `.exif.json` to the new TIF. Then copy the edited `.xmp` back over the archived one, first moving the old `.xmp` to the Trash. Every re-export writes the R5's EXIF again, so re-tag after each one. A second export of the same image gets a `_01` suffix, so tag the newest file.

## 6. Dust

- **Dark specks in the positive** were clear on the negative: something blocked light on the emulsion during exposure. Usually dust in the film camera; part of the film.
- **Bright specks or fibres in the positive** blocked the backlight during digitizing: dust or hair on the negative or the glass. Clean and re-scan.
- **To tell them apart,** compare two scans: specks that move with the image are on the film.

darktable **retouch** module:
- **heal** for open, smooth areas.
- **clone** near high-contrast edges (heal smears dark edges into bright water).
- **brush** for hairs.
- **Right-click** a shape to delete it.

darktable has no automatic dust detection. When a frame has many specks, offer a detection script instead of making the user click each one.

## 7. Comparing scans

For A/B comparison of two scans (different light, exposure, holder, etc.), use the **`print-image-check`** skill's `image-compare.sh`. Hold everything constant except the variable under test.

