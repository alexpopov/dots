# OpenRGB on zorn

Controls the Kingston Fury DDR4 RAM RGB on zorn (Fedora). The setup is a
**root daemon + non-root client** model so that everyday commands don't need
sudo.

## Architecture

OpenRGB needs root to talk to SMBus/i2c (where DDR4 RGB lives). Rather than
running every command with `sudo`, the server runs once as root and exposes
an SDK on port 6742; clients then talk to it as a regular user.

```
+----------------+              +---------------------+
|  cron / cli /  |  TCP 6742    |  openrgb --server   |
|   homebridge   | -----------> |   (systemd, root)   |
+----------------+              +---------------------+
                                          |
                                  SMBus / i2c (root only)
                                          |
                                  Kingston Fury DDR4
```

The server binds `0.0.0.0:6742` by default — i.e. anyone on the LAN can
control the RGB. Fine for a home network, worth knowing.

## Install on a fresh box

1. Install OpenRGB (`dnf install openrgb` on Fedora) — this also drops the
   massive `/usr/lib/udev/rules.d/60-openrgb.rules`.

2. Install the systemd unit:

   ```bash
   sudo cp openrgb-server.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable --now openrgb-server
   ```

3. Verify:

   ```bash
   systemctl status openrgb-server
   openrgb --client 127.0.0.1 --list-devices
   ```

4. Install the schedule (as the user, not root):

   ```bash
   crontab crontab.txt
   crontab -l   # confirm
   ```

## Usage

Device 0 is the RAM (verified via `--list-devices`).

```bash
# All on, rainbow
openrgb --client 127.0.0.1 -d 0 -m Rainbow --brightness 100

# Off (Static + black is more reliable than --brightness 0,
# since some firmwares ignore brightness=0)
openrgb --client 127.0.0.1 -d 0 -m Static -c 000000

# Solid color at half brightness
openrgb --client 127.0.0.1 -d 0 -m Static -c 00FF00 --brightness 50
```

The schedule (see `crontab.txt`):

- **17:00** — off
- **06:00** — Rainbow @ 100%

Runs every day. To restrict to weekdays, change `* * *` to `* * 1-5`.

## HomeKit toggle

HomeBridge runs in a podman container on zorn (`homebridge.service`), so
SSH-from-container patterns are awkward. Instead there's a tiny Python HTTP
wrapper on the host (`rgb-toggle`) that exposes three endpoints:

- `POST /rgb/on`     → Rainbow @ 100%
- `POST /rgb/off`    → Static black
- `GET  /rgb/state`  → `{"on": true|false}` from a state file

The HomeBridge container reaches the wrapper via `host.containers.internal`
(podman's host alias). The wrapper itself shells out to the openrgb client
on `127.0.0.1:6742`. State is persisted to `/var/lib/rgb-toggle/state` so
HomeKit shows the correct toggle position after restart.

### Install on zorn

```bash
sudo install -m 755 rgb-toggle.py /usr/local/bin/rgb-toggle
sudo cp rgb-toggle.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now rgb-toggle
sudo systemctl status rgb-toggle --no-pager | head -10
```

### Smoke test from the host

```bash
curl -s -X POST http://127.0.0.1:6743/rgb/on
curl -s http://127.0.0.1:6743/rgb/state
curl -s -X POST http://127.0.0.1:6743/rgb/off
```

### Smoke test from the homebridge container

```bash
podman exec homebridge curl -s -X POST http://host.containers.internal:6743/rgb/on
```

If `host.containers.internal` doesn't resolve from the container, use the
podman bridge gateway IP (find it with `podman inspect homebridge | grep
Gateway`) or zorn's LAN IP.

### HomeBridge UI config

In the HomeBridge UI (`http://zorn.local:8581`):

1. **Plugins** → search for and install `homebridge-http-switch`
2. **Accessories** (or via JSON config) — add an accessory with:

   ```json
   {
     "accessory": "HTTP-SWITCH",
     "name": "RAM RGB",
     "switchType": "stateful",
     "onUrl": "http://host.containers.internal:6743/rgb/on",
     "onMethod": "POST",
     "offUrl": "http://host.containers.internal:6743/rgb/off",
     "offMethod": "POST",
     "statusUrl": "http://host.containers.internal:6743/rgb/state",
     "statusPattern": "\"on\":\\s*true"
   }
   ```

3. Restart HomeBridge from the UI. The switch shows up in the Home app
   under whatever room HomeBridge is assigned to.

## Troubleshooting

- **Client hangs / can't connect** — server isn't running. Check
  `systemctl status openrgb-server`. The SDK port is 6742.
- **Brightness=0 doesn't go fully dark** — known firmware quirk on some
  modules; use `Static + 000000` instead.
- **First server start is slow** — openrgb probes every supported device
  type at boot. Subsequent client commands are fast.
- **RAM not detected after BIOS update** — the SMBus address can shift;
  restart the server (`sudo systemctl restart openrgb-server`).

## Files in this dir

- `openrgb-server.service` — systemd unit for the openrgb daemon
  (`/etc/systemd/system/openrgb-server.service`)
- `crontab.txt` — user crontab for the on/off schedule
- `rgb-toggle.py` — HTTP wrapper for HomeBridge
  (`/usr/local/bin/rgb-toggle`)
- `rgb-toggle.service` — systemd unit for the HTTP wrapper
  (`/etc/systemd/system/rgb-toggle.service`)
