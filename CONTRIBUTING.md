# Contributing

Thanks for improving `evwheelguard`.

Useful contributions include:

- Reports from different mice and Linux distributions.
- Better default tuning recommendations.
- Safer udev/systemd examples.
- Packaging for Fedora, Arch, Debian, Ubuntu, or Nix.
- Automated tests for the wheel debounce logic.

## Good bug reports

Please include:

- Linux distribution and version.
- Desktop session: Wayland or X11.
- Mouse model and connection type.
- `evwheelguard --list-devices` output.
- The command you used.
- A short `evtest` sample showing the wheel glitch.

## Development

Install editable:

```bash
python3 -m pip install -e .
```

Run the CLI:

```bash
evwheelguard --list-devices
```

Run syntax check:

```bash
python3 -m py_compile src/evwheelguard/cli.py
```
