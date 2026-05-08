# evwheelguard

`evwheelguard` is a small Linux userspace scroll-wheel stabilizer for mice that emit noisy or reversed wheel events.

It reads raw Linux `evdev` input from a physical mouse, filters short-lived opposite-direction wheel spikes, optionally scales scroll speed, and publishes a clean virtual mouse through `uinput`.

The original test case was a Logitech G Pro X / G Pro X Superlight-style LIGHTSPEED mouse on Fedora Wayland. The mouse felt normal on Windows, but on Linux the page sometimes jumped backward while scrolling in one direction.

> This is a software-side mitigation. It does not repair a broken encoder, firmware, or hardware. It filters the event stream before desktop applications see it.

---

## One-command install

For the default Logitech PRO X / G Pro X Superlight-style setup:

```bash
curl -fsSL https://raw.githubusercontent.com/zalaghi/evwheelguard/main/install.sh | sudo bash
```

With explicit tuning:

```bash
curl -fsSL https://raw.githubusercontent.com/zalaghi/evwheelguard/main/install.sh | sudo bash -s -- \
  --device-name "Logitech PRO X" \
  --lock-ms 140 \
  --scroll-mult 2
```

This installs dependencies, clones the repository to `/opt/evwheelguard`, creates `/usr/local/bin/evwheelguard`, writes `/etc/evwheelguard/config`, installs a root systemd service, enables it at boot, and starts it immediately.

Check status:

```bash
systemctl status evwheelguard.service --no-pager
journalctl -u evwheelguard.service -n 80 --no-pager
```

Change tuning after installation:

```bash
sudoedit /etc/evwheelguard/config
sudo systemctl restart evwheelguard.service
```

Uninstall:

```bash
curl -fsSL https://raw.githubusercontent.com/zalaghi/evwheelguard/main/uninstall.sh | sudo bash
```

### Maintainer note

This package is preconfigured for `https://github.com/zalaghi/evwheelguard`.

---

## The problem

Some mice emit short opposite-direction wheel events on Linux. A common symptom:

- You scroll up or down in one direction.
- The page briefly jumps the opposite way.
- Solaar or Piper may detect the mouse correctly.
- The raw event stream still contains wrong-direction wheel events.

You can confirm it with `evtest`:

```bash
sudo evtest /dev/input/event4 | grep --line-buffered -E 'REL_WHEEL|REL_WHEEL_HI_RES'
```

A noisy single-direction scroll can look like this:

```text
REL_WHEEL value -1
REL_WHEEL value -1
REL_WHEEL value 1   # unexpected opposite event
REL_WHEEL value -1
```

On another OS, vendor drivers or OS-level input processing may hide this noise. On Linux, many applications receive the lower-level input behavior more directly.

---

## What evwheelguard does

`evwheelguard`:

1. Opens the real mouse input device, for example `/dev/input/event4`.
2. Optionally grabs it so the noisy physical events do not reach applications.
3. Reads `EV_REL` wheel events frame by frame.
4. Drops opposite-direction wheel events that occur inside a configurable debounce window.
5. Optionally multiplies scroll speed.
6. Emits a clean virtual mouse using Linux `uinput`.

---

## Requirements

- Linux
- Python 3.10+
- `python-evdev`
- Read access to the target `/dev/input/eventX` device
- Write access to `/dev/uinput`

On Fedora:

```bash
sudo dnf install python3-evdev evtest
```

On Debian/Ubuntu:

```bash
sudo apt install python3-evdev evtest
```

---

## Quick start

Find your mouse input device:

```bash
sudo evtest
```

Look for the mouse name, for example:

```text
/dev/input/event4: Logitech PRO X
```

Run the filter:

```bash
sudo evwheelguard --device /dev/input/event4 --lock-ms 140 --scroll-mult 2
```

Keep the terminal open and test scrolling in a browser or document.

Stop with:

```bash
Ctrl+C
```

---

## Suggested defaults

For a Logitech PRO X / G Pro X Superlight-style issue on Fedora Wayland, this was a good starting point:

```bash
sudo evwheelguard --device /dev/input/event4 --lock-ms 140 --scroll-mult 2
```

Recommended tuning:

| Option | Meaning | Suggested range |
|---|---|---:|
| `--lock-ms` | Time window where opposite-direction wheel events are treated as bounce/noise | `80`-`250` |
| `--scroll-mult` | Scroll speed multiplier | `1`-`4` |
| `--name` | Name of the virtual input device | Any string |
| `--debug` | Print accepted/dropped wheel frames | Off by default |
| `--dry-run` | Analyze events without creating a virtual device | Off by default |
| `--list-devices` | Show input devices and exit | Off by default |

Use a higher `--lock-ms` if the wheel still jumps backward. Use a lower `--lock-ms` if changing scroll direction feels delayed.

---

## CLI examples

List input devices:

```bash
evwheelguard --list-devices
```

Filter a specific event device:

```bash
sudo evwheelguard --device /dev/input/event4 --lock-ms 140 --scroll-mult 2
```

Filter by name substring:

```bash
sudo evwheelguard --device-name "Logitech PRO X" --lock-ms 140 --scroll-mult 2
```

Debug dropped wheel events:

```bash
sudo evwheelguard --device /dev/input/event4 --debug
```

Dry-run without creating a virtual mouse:

```bash
sudo evwheelguard --device /dev/input/event4 --dry-run --debug
```

---

## Install from source

Clone the repository and install it editable:

```bash
git clone https://github.com/zalaghi/evwheelguard.git
cd evwheelguard
python3 -m pip install --user -e .
```

Then run:

```bash
sudo ~/.local/bin/evwheelguard --device /dev/input/event4 --lock-ms 140 --scroll-mult 2
```

If you install system-wide:

```bash
sudo python3 -m pip install .
sudo evwheelguard --device /dev/input/event4 --lock-ms 140 --scroll-mult 2
```

---

## systemd service example

A root system service example is included in:

```text
examples/evwheelguard.service
```

Copy it, edit the `--device` path, then enable it:

```bash
sudo cp examples/evwheelguard.service /etc/systemd/system/evwheelguard.service
sudo systemctl daemon-reload
sudo systemctl enable --now evwheelguard.service
```

Check logs:

```bash
journalctl -u evwheelguard.service -f
```

For a stable device path, prefer `/dev/input/by-id/...` when available.

---

## Fedora Wayland notes

Wayland is not the root cause here. If `evtest` shows wrong-direction wheel events, the issue exists before the desktop environment receives the event.

For Solaar/Piper:

- Solaar can detect Logitech HID++ devices, but it does not necessarily fix raw wheel bounce.
- Piper/libratbag can configure many gaming mice, but it usually does not debounce a noisy wheel event stream.
- `evwheelguard` sits lower in the userspace input path and filters the wheel events directly.

---

## Troubleshooting

### Permission denied on `/dev/input/eventX`

Run as root first:

```bash
sudo evwheelguard --device /dev/input/event4
```

For a non-root setup, you need proper udev rules or ACLs for the input event device and `/dev/uinput`.

### Permission denied on `/dev/uinput`

Check:

```bash
ls -l /dev/uinput
getfacl /dev/uinput
```

An example rule is included in:

```text
packaging/99-uinput.rules
```

### I get duplicate scrolling

Make sure the physical device is being grabbed. Do not use `--no-grab` for normal use.

### Direction changes feel delayed

Lower the debounce window:

```bash
sudo evwheelguard --device /dev/input/event4 --lock-ms 90
```

### Backward jumps still happen

Raise the debounce window:

```bash
sudo evwheelguard --device /dev/input/event4 --lock-ms 200
```

---

## Limitations

- This tool filters wheel events only.
- It does not change mouse firmware.
- It does not repair hardware.
- Very aggressive filtering can make intentional rapid direction changes feel delayed.
- It currently targets relative mouse devices using Linux `evdev` and `uinput`.

---

## License

MIT License. See [`LICENSE`](LICENSE).
