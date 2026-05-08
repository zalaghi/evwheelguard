#!/usr/bin/env python3
"""evwheelguard: filter noisy Linux scroll-wheel events through uinput."""

from __future__ import annotations

import argparse
import errno
import os
import signal
import sys
import time
from dataclasses import dataclass
from typing import Iterable, Optional

try:
    from evdev import InputDevice, UInput, ecodes, list_devices
except ImportError as exc:  # pragma: no cover
    raise SystemExit(
        "python-evdev is required. Install it with your package manager, "
        "for example: sudo dnf install python3-evdev"
    ) from exc


def _code(name: str) -> Optional[int]:
    """Return an evdev code by symbolic name, or None if unavailable."""
    return getattr(ecodes, name, None)


def _present(codes: Iterable[Optional[int]]) -> list[int]:
    return [c for c in codes if c is not None]


REL_WHEEL = _code("REL_WHEEL")
REL_WHEEL_HI_RES = _code("REL_WHEEL_HI_RES")
REL_HWHEEL = _code("REL_HWHEEL")
REL_HWHEEL_HI_RES = _code("REL_HWHEEL_HI_RES")

VERTICAL_WHEEL_CODES = set(_present([REL_WHEEL, REL_WHEEL_HI_RES]))
HORIZONTAL_WHEEL_CODES = set(_present([REL_HWHEEL, REL_HWHEEL_HI_RES]))
ALL_WHEEL_CODES = VERTICAL_WHEEL_CODES | HORIZONTAL_WHEEL_CODES

MOUSE_BUTTON_CODES = _present(
    [
        _code("BTN_LEFT"),
        _code("BTN_RIGHT"),
        _code("BTN_MIDDLE"),
        _code("BTN_SIDE"),
        _code("BTN_EXTRA"),
        _code("BTN_FORWARD"),
        _code("BTN_BACK"),
        _code("BTN_TASK"),
    ]
)

RELATIVE_CODES = _present(
    [
        _code("REL_X"),
        _code("REL_Y"),
        REL_WHEEL,
        REL_WHEEL_HI_RES,
        REL_HWHEEL,
        REL_HWHEEL_HI_RES,
    ]
)


def sign(value: int) -> int:
    if value > 0:
        return 1
    if value < 0:
        return -1
    return 0


def scale_value(value: int, multiplier: float) -> int:
    if multiplier == 1:
        return value
    scaled = int(round(value * multiplier))
    if value != 0 and scaled == 0:
        return sign(value)
    return scaled


def event_code_name(event_type: int, code: int) -> str:
    if event_type == ecodes.EV_REL:
        return ecodes.REL.get(code, f"REL_{code}")
    if event_type == ecodes.EV_KEY:
        return ecodes.KEY.get(code, f"KEY_{code}")
    return str(code)


@dataclass
class WheelDebouncer:
    lock_ms: float
    last_vertical_dir: int = 0
    last_vertical_time: float = 0.0
    last_horizontal_dir: int = 0
    last_horizontal_time: float = 0.0

    def should_drop(self, *, direction: int, now: float, horizontal: bool = False) -> bool:
        if direction == 0:
            return False

        if horizontal:
            last_dir = self.last_horizontal_dir
            last_time = self.last_horizontal_time
        else:
            last_dir = self.last_vertical_dir
            last_time = self.last_vertical_time

        dt_ms = (now - last_time) * 1000 if last_time else 999999.0

        if last_dir == 0 or direction == last_dir:
            if horizontal:
                self.last_horizontal_dir = direction
                self.last_horizontal_time = now
            else:
                self.last_vertical_dir = direction
                self.last_vertical_time = now
            return False

        if dt_ms < self.lock_ms:
            return True

        if horizontal:
            self.last_horizontal_dir = direction
            self.last_horizontal_time = now
        else:
            self.last_vertical_dir = direction
            self.last_vertical_time = now
        return False


def has_mouse_like_capability(dev: InputDevice) -> bool:
    caps = dev.capabilities(absinfo=False)
    rel_codes = set(caps.get(ecodes.EV_REL, []))
    key_codes = set(caps.get(ecodes.EV_KEY, []))
    return bool(rel_codes & {c for c in [REL_WHEEL, _code('REL_X'), _code('REL_Y')] if c is not None}) or bool(
        key_codes & set(MOUSE_BUTTON_CODES)
    )


def list_input_devices() -> int:
    for path in list_devices():
        try:
            dev = InputDevice(path)
            marker = "mouse-like" if has_mouse_like_capability(dev) else ""
            print(f"{path}\t{dev.name}\t{marker}".rstrip())
        except OSError as exc:
            print(f"{path}\t<unreadable: {exc}>")
    return 0


def find_device_by_name(substring: str) -> str:
    wanted = substring.lower()
    matches: list[tuple[str, str]] = []
    for path in list_devices():
        try:
            dev = InputDevice(path)
        except OSError:
            continue
        if wanted in dev.name.lower():
            matches.append((path, dev.name))

    if not matches:
        raise SystemExit(f"No input device matched name substring: {substring!r}")
    if len(matches) > 1:
        joined = "\n".join(f"  {path}\t{name}" for path, name in matches)
        raise SystemExit(
            "Multiple devices matched. Use --device with the exact event path:\n" + joined
        )
    return matches[0][0]


def build_uinput(name: str) -> UInput:
    cap = {
        ecodes.EV_KEY: MOUSE_BUTTON_CODES,
        ecodes.EV_REL: RELATIVE_CODES,
    }
    return UInput(cap, name=name, version=0x3)


def wheel_direction_from_frame(frame) -> tuple[int, int]:
    """Return (vertical_dir, horizontal_dir) for the current SYN frame."""
    vertical_dir = 0
    horizontal_dir = 0
    for event in frame:
        if event.type != ecodes.EV_REL:
            continue
        if event.code in VERTICAL_WHEEL_CODES and event.value:
            vertical_dir = sign(event.value)
        elif event.code in HORIZONTAL_WHEEL_CODES and event.value:
            horizontal_dir = sign(event.value)
    return vertical_dir, horizontal_dir


def run_filter(args: argparse.Namespace) -> int:
    device_path = args.device or find_device_by_name(args.device_name)

    try:
        dev = InputDevice(device_path)
    except OSError as exc:
        raise SystemExit(f"Could not open {device_path}: {exc}") from exc

    ui = None
    if not args.dry_run:
        try:
            ui = build_uinput(args.name)
        except OSError as exc:
            hint = ""
            if exc.errno in (errno.EACCES, errno.EPERM):
                hint = "\nCheck write access to /dev/uinput or run with sudo."
            raise SystemExit(f"Could not create uinput device: {exc}{hint}") from exc

    debouncer = WheelDebouncer(lock_ms=args.lock_ms)
    stop = False

    def handle_signal(signum, frame):  # noqa: ARG001
        nonlocal stop
        stop = True

    signal.signal(signal.SIGINT, handle_signal)
    signal.signal(signal.SIGTERM, handle_signal)

    if args.grab:
        try:
            dev.grab()
        except OSError as exc:
            hint = ""
            if exc.errno in (errno.EACCES, errno.EPERM):
                hint = "\nTry running with sudo or adjust input device permissions."
            if ui is not None:
                ui.close()
            raise SystemExit(f"Could not grab {device_path}: {exc}{hint}") from exc

    print(f"Input device : {device_path} ({dev.name})")
    if args.dry_run:
        print("Mode         : dry-run, no virtual device")
    else:
        print(f"Output device: {args.name}")
    print(f"lock-ms      : {args.lock_ms}")
    print(f"scroll-mult  : {args.scroll_mult}")
    print(f"grab         : {args.grab}")
    print("Press Ctrl+C to stop.")

    frame = []
    try:
        for event in dev.read_loop():
            if stop:
                break

            if event.type == ecodes.EV_SYN and event.code == ecodes.SYN_REPORT:
                now = time.monotonic()
                vertical_dir, horizontal_dir = wheel_direction_from_frame(frame)
                drop_vertical = debouncer.should_drop(direction=vertical_dir, now=now, horizontal=False) if vertical_dir else False
                drop_horizontal = debouncer.should_drop(direction=horizontal_dir, now=now, horizontal=True) if horizontal_dir else False

                wrote = False
                for item in frame:
                    if item.type not in (ecodes.EV_KEY, ecodes.EV_REL):
                        continue

                    if item.type == ecodes.EV_REL:
                        if item.code in VERTICAL_WHEEL_CODES and drop_vertical:
                            if args.debug:
                                print(f"drop vertical {event_code_name(item.type, item.code)} value={item.value}")
                            continue
                        if item.code in HORIZONTAL_WHEEL_CODES and drop_horizontal:
                            if args.debug:
                                print(f"drop horizontal {event_code_name(item.type, item.code)} value={item.value}")
                            continue

                    out_value = item.value
                    if item.type == ecodes.EV_REL and item.code in ALL_WHEEL_CODES:
                        out_value = scale_value(item.value, args.scroll_mult)
                        if args.debug:
                            print(
                                f"wheel {event_code_name(item.type, item.code)} "
                                f"in={item.value} out={out_value}"
                            )

                    if ui is not None:
                        ui.write(item.type, item.code, out_value)
                        wrote = True

                if ui is not None and wrote:
                    ui.syn()
                frame = []
            else:
                frame.append(event)
    finally:
        if args.grab:
            try:
                dev.ungrab()
            except OSError:
                pass
        if ui is not None:
            ui.close()
        print("Stopped evwheelguard.")

    return 0


def positive_float(value: str) -> float:
    parsed = float(value)
    if parsed <= 0:
        raise argparse.ArgumentTypeError("must be greater than 0")
    return parsed


def non_negative_float(value: str) -> float:
    parsed = float(value)
    if parsed < 0:
        raise argparse.ArgumentTypeError("must be >= 0")
    return parsed


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="evwheelguard",
        description="Filter noisy Linux scroll-wheel events and emit a clean virtual mouse through uinput.",
    )
    target = parser.add_mutually_exclusive_group()
    target.add_argument("--device", help="Input event device, for example /dev/input/event4")
    target.add_argument("--device-name", help="Unique substring of the input device name")
    parser.add_argument("--list-devices", action="store_true", help="List input devices and exit")
    parser.add_argument(
        "--lock-ms",
        type=non_negative_float,
        default=140.0,
        help="Drop opposite-direction wheel events inside this many milliseconds. Default: 140",
    )
    parser.add_argument(
        "--scroll-mult",
        type=positive_float,
        default=1.0,
        help="Multiply wheel event values. Try 2 for faster scrolling. Default: 1",
    )
    parser.add_argument(
        "--name",
        default="evwheelguard filtered mouse",
        help="Name of the virtual output device.",
    )
    parser.add_argument("--debug", action="store_true", help="Print wheel filtering decisions")
    parser.add_argument("--dry-run", action="store_true", help="Read and analyze events without creating uinput output")
    parser.add_argument(
        "--no-grab",
        dest="grab",
        action="store_false",
        help="Do not grab the physical input device. This usually causes duplicate scrolling.",
    )
    parser.set_defaults(grab=True)
    return parser


def main(argv: Optional[list[str]] = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)

    if args.list_devices:
        return list_input_devices()

    if not args.device and not args.device_name:
        parser.error("one of --device, --device-name, or --list-devices is required")

    return run_filter(args)


if __name__ == "__main__":  # pragma: no cover
    raise SystemExit(main())
