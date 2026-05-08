# Fedora Wayland notes

## Solaar/Piper can work while scroll still glitches

For Logitech devices, Solaar may show the receiver and mouse correctly. Piper may also configure DPI or profiles. That does not guarantee the raw wheel event stream is clean.

If the issue appears in `evtest`, it is happening before applications receive the event.

## Check uinput

```bash
ls -l /dev/uinput
getfacl /dev/uinput
```

A working user ACL may look like:

```text
user:YOUR_USER:rw-
```

For root service usage, `sudo evwheelguard ...` is usually simpler.

## Known-good test command

```bash
sudo evwheelguard --device /dev/input/event4 --lock-ms 140 --scroll-mult 2
```

## Tuning

- If changing direction feels delayed: lower `--lock-ms`.
- If backward jumps still occur: raise `--lock-ms`.
- If scrolling is too slow: raise `--scroll-mult`.
- If scrolling is too fast: lower `--scroll-mult`.
