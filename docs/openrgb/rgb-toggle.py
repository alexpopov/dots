#!/usr/bin/env python3
"""rgb-toggle: tiny HTTP wrapper around the openrgb client for HomeBridge.

Endpoints
  POST /rgb/on     -> Rainbow @ 100%, returns {"on": true}
  POST /rgb/off    -> Static black,   returns {"on": false}
  GET  /rgb/state  -> {"on": <bool>}  read from on-disk state file

Configuration via env vars (defaults shown):
  RGB_BIND=0.0.0.0:6743
  OPENRGB_BIN=/usr/bin/openrgb
  OPENRGB_HOST=127.0.0.1            # openrgb-server we talk to
  RGB_DEVICE=0                       # device index (0 = Kingston RAM)
  RGB_STATE=/var/lib/rgb-toggle/state

Binds to 0.0.0.0 by default so the homebridge podman container can reach it
via host.containers.internal. The openrgb server it fronts is already on
0.0.0.0:6742 with no auth, so this wrapper doesn't change the exposure
posture for the home LAN.
"""
import json
import os
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

OPENRGB_BIN = os.environ.get("OPENRGB_BIN", "/usr/bin/openrgb")
OPENRGB_HOST = os.environ.get("OPENRGB_HOST", "127.0.0.1")
DEVICE = os.environ.get("RGB_DEVICE", "0")
STATE_FILE = os.environ.get("RGB_STATE", "/var/lib/rgb-toggle/state")
BIND = os.environ.get("RGB_BIND", "0.0.0.0:6743")

ON_CMD = [OPENRGB_BIN, "--client", OPENRGB_HOST,
          "-d", DEVICE, "-m", "Rainbow", "--brightness", "100"]
OFF_CMD = [OPENRGB_BIN, "--client", OPENRGB_HOST,
           "-d", DEVICE, "-m", "Static", "-c", "000000"]


def write_state(on):
    os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
    with open(STATE_FILE, "w") as f:
        f.write("1" if on else "0")


def read_state():
    try:
        with open(STATE_FILE) as f:
            return f.read().strip() == "1"
    except FileNotFoundError:
        return False


def run(cmd):
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=15)
        return r.returncode, (r.stdout + r.stderr).strip()
    except Exception as e:
        return 1, str(e)


class Handler(BaseHTTPRequestHandler):
    def _json(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _set(self, on):
        rc, out = run(ON_CMD if on else OFF_CMD)
        if rc != 0:
            self._json(502, {"error": "openrgb failed", "detail": out})
            return
        write_state(on)
        self._json(200, {"on": on})

    def _route(self):
        if self.path == "/rgb/on":
            self._set(True)
        elif self.path == "/rgb/off":
            self._set(False)
        elif self.path == "/rgb/state":
            self._json(200, {"on": read_state()})
        else:
            self._json(404, {"error": "not found"})

    do_GET = _route
    do_POST = _route

    def log_message(self, fmt, *args):
        sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))


def main():
    host, port = BIND.rsplit(":", 1)
    ThreadingHTTPServer((host, int(port)), Handler).serve_forever()


if __name__ == "__main__":
    main()
