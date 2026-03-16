#!/usr/bin/env bash
set -euo pipefail

# Bootstrap whisper dictation setup.
# Requirements: Linux, Wayland, NVIDIA GPU, PipeWire, uv
# Tested on: Fedora 42 + KDE Plasma 6
#
# Environment variables (optional):
#   WHISPER_MODEL   - Model size: tiny, base, small, medium, large-v3 (default: medium)
#   WHISPER_DEVICE  - Device: cuda, cpu (default: cuda)
#   WHISPER_COMPUTE - Compute type: float32, int8_float32, int8, float16 (default: int8_float32)

DIR="$(cd "$(dirname "$0")" && pwd)"
WHISPER_MODEL="${WHISPER_MODEL:-medium}"

echo "=== Whisper Dictation Bootstrap (model: $WHISPER_MODEL) ==="

# Check prerequisites
for cmd in pw-record socat wl-copy notify-send uv; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Missing: $cmd"
        echo "Install with: sudo dnf install pipewire-utils socat wl-clipboard libnotify uv"
        exit 1
    fi
done

if ! command -v ydotool &>/dev/null; then
    echo "Missing: ydotool"
    echo "Install with: sudo dnf install ydotool"
    exit 1
fi

if ! nvidia-smi &>/dev/null; then
    echo "No NVIDIA GPU detected. This setup requires CUDA."
    exit 1
fi

# Create venv with faster-whisper
VENV="$HOME/.local/share/venvs/whisper"
if [ ! -d "$VENV" ]; then
    echo "Creating whisper venv..."
    uv venv "$VENV"
fi
echo "Installing faster-whisper..."
uv pip install --python "$VENV/bin/python" faster-whisper nvidia-cublas-cu12 nvidia-cudnn-cu12

# Find NVIDIA lib paths for LD_LIBRARY_PATH in systemd service
NVIDIA_LIBS=$("$VENV/bin/python" -c "
import os, nvidia.cublas, nvidia.cudnn
cublas = os.path.join(nvidia.cublas.__path__[0], 'lib')
cudnn = os.path.join(nvidia.cudnn.__path__[0], 'lib')
print(cublas + ':' + cudnn)
")

# Install scripts
echo "Installing scripts to ~/.local/bin/..."
install -m755 "$DIR/bin/dictate" "$HOME/.local/bin/dictate"
install -m755 "$DIR/bin/whisper-server.py" "$HOME/.local/bin/whisper-server.py"

# Install systemd services
echo "Installing systemd user services..."
mkdir -p "$HOME/.config/systemd/user"

cp "$DIR/config/systemd/user/ydotool.service" "$HOME/.config/systemd/user/ydotool.service"

# whisper-server needs LD_LIBRARY_PATH for NVIDIA pip libs — patch the service file
WHISPER_ENVS="Environment=LD_LIBRARY_PATH=$NVIDIA_LIBS"
WHISPER_ENVS="$WHISPER_ENVS\nEnvironment=WHISPER_MODEL=${WHISPER_MODEL}"
[ -n "${WHISPER_DEVICE:-}" ] && WHISPER_ENVS="$WHISPER_ENVS\nEnvironment=WHISPER_DEVICE=${WHISPER_DEVICE}"
[ -n "${WHISPER_COMPUTE:-}" ] && WHISPER_ENVS="$WHISPER_ENVS\nEnvironment=WHISPER_COMPUTE=${WHISPER_COMPUTE}"
sed "s|^ExecStart=.*|${WHISPER_ENVS}\nExecStart=$VENV/bin/python $HOME/.local/bin/whisper-server.py|" \
    "$DIR/config/systemd/user/whisper-server.service" > "$HOME/.config/systemd/user/whisper-server.service"

# Enable and start services
systemctl --user daemon-reload
systemctl --user enable --now ydotool.service
systemctl --user enable --now whisper-server.service

echo ""
echo "=== Done ==="
echo "The whisper model takes ~20s to load on first start."
echo "Bind ~/.local/bin/dictate to a key (e.g. F9) in your DE settings."
echo "Press once to record, press again to stop and paste transcription."
