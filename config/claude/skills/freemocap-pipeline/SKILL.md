---
name: freemocap-pipeline
description: Markerless motion capture with FreeMoCap 1.8.2 from phone footage - ChArUco board checks, camera calibration, take grading, MediaPipe tracking, skeleton previews. Use ONLY when the user says mocap, motion capture, FreeMoCap, ChArUco/charuco, or points at a MoCap take folder (e.g. ~/Desktop/MoCap/TakeN).
version: 1.1.0
---

# FreeMoCap Pipeline

Markerless mocap from clips shot on phones, synced on an audio clap. FreeMoCap
1.8.2 is installed as a pip package in `.venv/` of **`~/Development/freemocap`**
(git repo); every command below runs from that directory, and every script named
here lives there. Takes live under `~/Desktop/MoCap/TakeN/`, each with its own
README of numbers. The GUI is unnecessary — the scripts drive the library directly.

**Pinned to 1.8.2 deliberately.** Several scripts reach into internals
(`AniposeCameraCalibrator`, `ProcessingParameterModel`, a `cpu_count` patch)
rather than a public API. Upgrading will break them.

## Setup

```bash
./bootstrap.sh              # macOS / Linux / WSL2
.venv/bin/python doctor.py  # verify: python, freemocap, opencv, ffmpeg, rsvg, torch
```

`.venv/` is disposable — delete and re-bootstrap to rebuild exactly. `ffmpeg` is
required (the import wizard disables sync without it) and `rsvg-convert` is needed
by `make_board.py`.

## The board

FreeMoCap accepts **exactly two geometries** — `7x5 Charuco` and `5x3 Charuco` —
and the marker dictionary is hardcoded `DICT_4X4_250`. A board with 5x5 or 6x6
markers detects **nothing**. Most off-the-shelf machine-vision targets are the
wrong dictionary, wrong grid, or both.

**Never put two boards in one frame.** Both geometries number their markers from
0, so IDs collide and corner interpolation returns zero. This fails silently.

Alp's known-good PDFs (correct dictionary, A0 through Letter, both geometries):
`~/Library/Mobile Documents/com~apple~CloudDocs/Downloads/ChaRuCo Patterns/PDFs/`.
A3 7x5 gives 54mm squares.

```bash
uv run check_board.py --list          # enumerate cameras
uv run check_board.py                 # live check; `n` cycles cameras
uv run check_board.py shot.jpg        # a still from each real camera position
uv run make_board.py --board 5x3      # tiled print with overlapping seams
```

`check_board.py` reports **px per module** (floor ~3, want 4+) and names the wrong
dictionary when one is used. A webcam test validates the print but *not* range —
always check a still from where the camera will actually stand.

## Shooting

One continuous clip per phone: clap, board sweep, set board down, perform, stop.

- **Same resolution across calibration and take** — intrinsics are in pixel units.
  Frame rate may differ between them; resolution may not.
- **4K.** Portrait is fine and better for a standing figure; OpenCV honours the
  iPhone rotation tag. 1080p leaves too few px/module at room distances.
- **Match the lenses.** Phones on different lenses (one zoomed) shrink the shared
  volume badly. Check the solved focal lengths afterwards.
- **Shared volume is the constraint.** Calibration pairs cameras only on frames
  where *both* see the board. Solo passes help that camera's intrinsics but
  contribute nothing to extrinsics.
- **60fps** for fast motion — it also caps shutter time, halving motion blur
  versus 30. More light shortens it further; blur hurts more than frame rate.
- Three cameras beats two. With two there is no redundancy: any limb one camera
  loses has no fallback.

## Grade the footage before processing

```bash
uv run take_report.py ~/Desktop/MoCap/Take3
```

Reports sync offset and confidence, then **seconds where every camera clears 6
corners simultaneously**. >=30 solves well, 15-30 is workable, under 15 means
reshoot. Also flags low-resolution portrait and frame-rate mismatches.

## Process

Cut the calibration and take segments from the source clips using the sync offset
`take_report.py` found. Then:

```bash
.venv/bin/python calibrate.py <folder>/synchronized_videos <square_mm>
.venv/bin/python process.py   <folder>          # MediaPipe + triangulation
.venv/bin/python resmooth.py  <folder> 60 6     # folder, true fps, cutoff Hz
.venv/bin/python blend.py     <folder>          # -> <folder>/<name>.blend
```

Calibration is geometric, not temporal — decimate it to ~5fps (never in
resolution) to cut detection time by an order of magnitude. Judge the result by
reprojection error: **under 1px is good**.

`square_mm` sets the absolute scale of everything downstream. Getting it wrong
still solves perfectly — same reprojection error, wrong-sized human. It is a pure
scale factor, so a later correction needs no reprocessing.

## Render previews

```bash
"/Applications/Blender.app/Contents/MacOS/Blender" -b <blend> --python render.py \
    -- out.mp4 720 1280 --follow
```

`--follow` rides the hips so the figure stays large; without it the camera must
frame the whole path and the subject goes tiny in a narrow frame. Hides the
`*_mediapipe` footage billboards, which otherwise swamp the shot.

Because the per-camera clips and the render cover identical frames, a comparison
triptych is a straight `hstack` with no offset:

```bash
ffmpeg -i cam_0.mp4 -i skeleton_portrait.mp4 -i cam_1.mp4 -filter_complex \
 "[0:v]fps=60,scale=720:1280,setsar=1[l];[1:v]fps=60,scale=720:1280,setsar=1[m];\
  [2:v]fps=60,scale=720:1280,setsar=1[r];[l][m][r]hstack=inputs=3[v]" \
 -map "[v]" -c:v libx264 -crf 20 -pix_fmt yuv420p -r 60 triptych.mp4
```

Watching the skeleton against the real footage is the best drift diagnostic there is.

## Traps

Every one of these fails silently or reports the wrong cause.

| Symptom | Real cause |
|---|---|
| `ImportError: cannot import name 'logger' from partially initialized module` | A freemocap submodule (or a package pulling one in) was imported before `import freemocap` completed. Import the package first, in full. |
| Endless `RuntimeError: An attempt has been made to start a new process...` | Board detection fans out over processes; macOS spawn re-imports your script and spawns during its own import. A `__main__` guard does **not** fix it. Pin `multiprocessing.cpu_count` and `skellytracker.process_folder_of_videos.cpu_count` to 2 so `num_processes` resolves to 1. |
| `FileNotFoundError: Could not find synchronized_videos folder` (folder exists) | Cameras have **unequal frame counts**. `check_synchronized_videos_status` asserts equality and reports any `AssertionError` as a missing folder. Cut by frame count (`-frames:v N`), not by time. |
| Smoothing barely smooths | `PostProcessingParametersModel.framerate` and `ButterworthFilterParametersModel.sampling_rate` both default to **30**. At 60fps the real cutoff doubles. Pass the true rate. |
| `TypeError: enum "FFMPEG" not found` in Blender | Blender 5.x needs `image_settings.media_type = "VIDEO"` before `FFMPEG` appears in the `file_format` enum. |
| `Could not find Blender executable` | The path `/Applications/Blender.app` is hardcoded. Symlink a versioned install to it. |
| Board renders but detects 4/24 corners | `cv2.aruco.CharucoBoard.generateImage()` in OpenCV 4.8 puts markers on the opposite square parity. Use the shipped SVGs in `board/`. |
| `ModuleNotFoundError` for a stdlib module | A scratch file shadows it — the script's own directory goes on `sys.path`. Never name a helper `inspect.py`, `json.py`, etc. |

## Reading the output

`output_data/` holds body, face, and both hands as `.npy` and `.csv`, plus
`joint_angles.csv` and centre-of-mass.

Two different failure modes, and only one is fixable by smoothing:

- **Jitter** — high-frequency, shows up as frame-to-frame acceleration. The
  Butterworth filter fixes it (~40-60% reduction at the correct sampling rate).
- **Depth error** — low-frequency, shows up as bone lengths that breathe (~10% on
  a two-camera rig). A low-pass filter passes it straight through. Use
  `mediapipe_rigid_bones_3d.npy`, which forces constant bone lengths.

Per-landmark reprojection error tells you where the rig is weakest. On two
cameras, expect knees, elbows and feet to be worst — those are the joints one
camera loses first.
