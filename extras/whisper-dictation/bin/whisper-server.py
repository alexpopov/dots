#!/usr/bin/env python3
"""Persistent whisper transcription server. Keeps model in VRAM."""

import socket
import os
from faster_whisper import WhisperModel

SOCKET_PATH = "/tmp/whisper-server.sock"
MODEL_SIZE = os.environ.get("WHISPER_MODEL", "medium")
DEVICE = os.environ.get("WHISPER_DEVICE", "cuda")
COMPUTE = os.environ.get("WHISPER_COMPUTE", "int8_float32")

model = WhisperModel(MODEL_SIZE, device=DEVICE, compute_type=COMPUTE)
print("Model loaded, listening on", SOCKET_PATH)

if os.path.exists(SOCKET_PATH):
    os.unlink(SOCKET_PATH)

srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(SOCKET_PATH)
srv.listen(1)

while True:
    conn, _ = srv.accept()
    data = conn.recv(4096).decode().strip()
    if not data or not os.path.exists(data):
        conn.sendall(b"")
        conn.close()
        continue
    try:
        segments, _ = model.transcribe(data, beam_size=1, language="en")
        text = " ".join(seg.text.strip() for seg in segments)
    except Exception as e:
        text = ""
        print(f"Error: {e}")
    try:
        conn.sendall(text.encode())
    except BrokenPipeError:
        print("Client disconnected before response")
    conn.close()
