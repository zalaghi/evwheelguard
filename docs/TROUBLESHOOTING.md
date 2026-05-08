# Troubleshooting

## Confirm the raw wheel problem

Run:

```bash
sudo evtest /dev/input/event4 | grep --line-buffered -E 'REL_WHEEL|REL_WHEEL_HI_RES'
```

Scroll only one direction. If both positive and negative values appear, your raw event stream is noisy.

## The virtual mouse appears but nothing moves

Make sure your desktop sees the virtual `uinput` device. Run:

```bash
sudo libinput list-devices | grep -A5 -i evwheelguard
```

If unavailable, install libinput tools for your distribution.

## Duplicate scrolling

Normal use should grab the physical device. Do not use `--no-grab` unless you are debugging.

## The mouse stops working while testing

Stop the program with `Ctrl+C`. If the terminal is not focused, switch to keyboard input or another mouse and stop the process:

```bash
sudo pkill -f evwheelguard
```

## Device path changes after reboot

Use a stable path from:

```bash
ls -l /dev/input/by-id/
```

Then use that path in the systemd service.
