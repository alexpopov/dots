# Whisper Dictation

Toggle-style voice dictation using faster-whisper on NVIDIA GPUs.
Press a key to start recording, press again to transcribe and paste.

## Requirements

- Linux + Wayland (KDE Plasma tested)
- NVIDIA GPU (CUDA, no float16 needed)
- PipeWire (for audio recording)
- uv (Python package manager)

### System packages (Fedora)

```
sudo dnf install ydotool socat wl-clipboard pipewire-utils libnotify
```

## Install

```
./bootstrap.sh
```

Then bind `~/.local/bin/dictate` to a key (e.g. F9) in your DE settings.

### Model selection

Set `WHISPER_MODEL` before running bootstrap to choose a different model:

```
WHISPER_MODEL=small ./bootstrap.sh    # ~460MB VRAM, faster, less accurate
WHISPER_MODEL=medium ./bootstrap.sh   # ~1.8GB VRAM, default
WHISPER_MODEL=large-v3 ./bootstrap.sh # ~3GB VRAM, best quality
```

Other environment variables:

| Variable | Default | Options |
|---|---|---|
| `WHISPER_MODEL` | `medium` | `tiny`, `base`, `small`, `medium`, `large-v3` |
| `WHISPER_DEVICE` | `cuda` | `cuda`, `cpu` |
| `WHISPER_COMPUTE` | `int8_float32` | `float32`, `int8_float32`, `int8`, `float16` |

To change the model later, edit `Environment=WHISPER_MODEL=...` in
`~/.config/systemd/user/whisper-server.service` and run
`systemctl --user restart whisper-server`.

## How it works

```
bin/
  dictate              # Toggle script: record -> transcribe -> paste
  whisper-server.py    # Persistent GPU server keeping model in VRAM
config/
  systemd/user/
    whisper-server.service  # Keeps whisper-server.py running
    ydotool.service         # Keeps ydotoold running (Wayland input simulation)
```

1. `dictate` (first press): starts `pw-record`, shows "Recording..." notification
2. `dictate` (second press): stops recording, sends WAV path to whisper-server
   over Unix socket, copies result to clipboard, simulates Ctrl+V via ydotool
3. `whisper-server.py`: loads the whisper model once into VRAM, listens on
   `/tmp/whisper-server.sock`

## Notes

- First boot takes ~20s for the medium model to load
- WAV files are temporary (`/tmp/dictate.wav`), deleted after transcription
- Transcription log at `/tmp/dictate.log` (cleared on reboot)
- Uses `nvidia-cublas-cu12` / `nvidia-cudnn-cu12` pip packages with
  LD_LIBRARY_PATH (no system CUDA toolkit needed)
- GPU must support the chosen compute type (e.g. GTX 1070 doesn't support
  float16, use int8_float32 or float32)
