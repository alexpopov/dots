---
name: qfil-flashing
description: 'Use this skill when QFIL/EDL-flashing a Meta VR device (Stanley, etc.) that is unresponsive or bricked — downloading the QFIL package with maui, detecting EDL (Qualcomm 9008) mode, dealing with secure-boot vs --insecure, and the macOS/Rosetta gotchas. Covers the key escape hatch: when `maui qfil-flash` keeps stalling, run the cached `flash_qfil_package.py` directly on a quiet USB bus.'
---

# QFIL / EDL flashing (Meta VR devices, e.g. Stanley) on macOS

QFIL = Qualcomm Flash Image Loader. Last-resort flash for a corrupted/unresponsive
device via **EDL (Emergency Download) mode**, where the SoC enumerates as USB
`05c6:9008` (Qualcomm HS-USB QDLoader 9008) and speaks the **Sahara → Firehose**
protocol.

## THE key lesson (read this first)

**When `maui qfil-flash` repeatedly dies during the handshake — run the script directly.**

`maui qfil-flash` calls a cached `flash_qfil_package.py`, but it does so under
`sudo` + `fbpython`, deletes the USB trace afterward, and may probe the device
concurrently. If it keeps stalling at the signed-digest / `<configure>` step, drop
to the cached package and run it yourself on a **quiet, exclusive USB bus**:

```bash
cd ~/.maui/cache/builds/stanley-qfil_<build>-<id>/
./flash_qfil_package.py --secure       # secure-boot device (the default/common case)
```

This has worked when maui would not. Nothing else may touch USB while it runs
(kill any watch loops, `lsqdl` pollers, `system_profiler`/`ioreg` loops).

## Download / cache the package with maui

`-w`/`--hardware-type` is a **`list-builds`** flag, NOT a `qfil-flash` flag.

```bash
# find a build number (QFIL packages are usually the 'user' flavor)
maui list-builds -w stanley -q -i -n 5          # -q=qfil, -i=ignore LKG/STU filter
# flavor trailing digit: user = ...2030, userdebug = ...2031

# download + unpack into cache (no device needed)
maui qfil-flash --cache-only -n <build-number>
```

Cached package lands at `~/.maui/cache/builds/stanley-qfil_<build>-<id>/` and
contains `flash_qfil_package.py`, `lsqdl`, `kickstart*`, `fh_loader*`, the images,
and the signing blobs (`FullDigestsToSign.bin.mbn`, `ChainedTableOfFullDigests.bin`).

## Detect EDL / 9008 mode

Authoritative probe = the package's own IOKit scanner:

```bash
cd ~/.maui/cache/builds/stanley-qfil_<build>-<id>/
xattr -rd com.apple.quarantine ./lsqdl        # --test-scan returns BEFORE the script's
./flash_qfil_package.py --test-scan           # own quarantine step, so clear it yourself
# -> "QDL Device Found: ['usb:...X']"  (empty [] = not in EDL)
```

Quick raw checks (no package needed):
```bash
system_profiler SPUSBDataType 2>/dev/null | grep -ic '0x05c6.*0x9008\|QDLoader'
ioreg -p IOUSB -l | grep -E '"idVendor" = 1478|"idProduct" = 36872'   # 1478=0x05c6 36872=0x9008
```

A reusable polling loop lives alongside this skill:
```bash
${CLAUDE_SKILL_DIR}/watch_qfil.sh        # announces PRESENT/GONE transitions
```
**Do NOT run this (or any USB enumeration) during an actual flash** — concurrent
opens reset the interface mid-handshake and cause `usb_read` timeouts.

Force EDL on Stanley: plug USB-C, expose the pinhole, hold **PINHOLE + PWR ~20 s**,
release. Device shows no LEDs in EDL. Window can be <20 s — proceed promptly.

## Secure boot vs --insecure

Most Meta silicon is **secure-boot fused — even EVT units** (fuses are in the
production key domain regardless of the "eVT2" enclosure label). The device proves
it by loading `xbl_s_devprg_ns.melf` (the `_s_` = secure programmer) and demanding
signed digests.

- **Default = secure**: sends `--signeddigests=FullDigestsToSign.bin.mbn
  --chaineddigests=ChainedTableOfFullDigests.bin`. Use this.
- **`--insecure` on a secure device fails instantly** with:
  ```
  TARGET SAID: 'ERROR: VIP img authentication failed ... Verifying signature failed with 7'
  ```
  Reaching `<configure>` in insecure mode is NOT progress — it's a guaranteed
  rejection. There is no software override for a fused-secure SoC.

If a *secure* run reaches the target and the target rejects the **signed** digests
(not a timeout) → package↔fuse key/anti-rollback mismatch; you need the correct
signed package for that unit (ask whoever provisioned it). A prod `user` package
flashing fine means the unit is prod-fused.

## Reading the log: what's fatal, what's noise

- `ERROR: usb_read failed with status e0004051` **once at startup** (right after
  "opened port") = **benign** `--readbogusdata` flush. It appears in *successful*
  flashes too. Not the failure.
- `WARNING: Timeout - no response trying to read from target` at the very **end**,
  after `Sending <power>` = **benign**; the device reset and stopped answering.
  Look for `{All Finished Successfully}`.
- **Real progress** = `TARGET SAID: 'INFO: Calling handler for program'` plus
  climbing `{percent files transferred}`. Firehose is synchronous, so **no
  percentages = nothing is being written** (it is NOT silently flashing in the
  background). A failure at/before `<configure>` touches zero partitions — safe to
  Ctrl-C, replug, retry.

## macOS / Apple Silicon gotchas

- Binaries are **x86_64** → run via **Rosetta** (`arch -x86_64 ./kickstart_darwin`,
  `./fh_loader_darwin`). The script does this automatically.
- Clear quarantine on the three binaries (script does this for the real flash, but
  `--test-scan` returns first): `xattr -rd com.apple.quarantine ./fh_loader_darwin ./lsqdl ./kickstart_darwin`
- Use a **known-good full-pin USB-C cable, direct to the Mac** (no hub/dock). USB 2.0
  paths are more reliable for Firehose than USB 3.x.
- If direct-on-a-quiet-bus still stalls, a **Linux/Windows host removes Rosetta** and
  is the most reliable Firehose host — and its `port_trace.txt` isn't auto-deleted.

## After a successful flash

Device issues its own `<power>` reset. First boot post-QFIL is slow (minutes, maybe
a couple reboots). Don't unplug. Watch with adb — **not** the qfil watcher:
```bash
while :; do adb devices; sleep 3; done
```
