#!/usr/bin/env bash
set -euo pipefail

DEVICE="${1:-/dev/input/event4}"
LOCK_MS="${LOCK_MS:-140}"
SCROLL_MULT="${SCROLL_MULT:-2}"

exec sudo evwheelguard --device "$DEVICE" --lock-ms "$LOCK_MS" --scroll-mult "$SCROLL_MULT" --debug
