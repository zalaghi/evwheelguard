#!/usr/bin/env bash
set -euo pipefail

DEFAULT_REPO_URL="https://github.com/YOUR_USERNAME/evwheelguard.git"
REPO_URL="${EVWHEELGUARD_REPO:-$DEFAULT_REPO_URL}"
BRANCH="${EVWHEELGUARD_BRANCH:-main}"
INSTALL_DIR="/opt/evwheelguard"
DEVICE=""
DEVICE_NAME="Logitech PRO X"
LOCK_MS="140"
SCROLL_MULT="2"
OUTPUT_NAME="evwheelguard filtered mouse"
DEBUG="0"
START_SERVICE="1"
ENABLE_SERVICE="1"
SKIP_PACKAGES="0"

usage() {
  cat <<'EOF'
evwheelguard installer

Usage:
  curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/evwheelguard/main/install.sh | sudo bash

Common tuning:
  curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/evwheelguard/main/install.sh | sudo bash -s -- \
    --device-name "Logitech PRO X" --lock-ms 140 --scroll-mult 2

Options:
  --repo URL           Git repository URL. Default is built into this script.
  --branch NAME        Git branch to install. Default: main
  --install-dir PATH   Install directory. Default: /opt/evwheelguard
  --device PATH        Exact input event path, for example /dev/input/event4
  --device-name TEXT   Input device name substring. Default: Logitech PRO X
  --lock-ms MS         Debounce window. Higher = stronger filtering, more delay. Default: 140
  --scroll-mult N      Scroll speed multiplier. Default: 2
  --name TEXT          Virtual device name. Default: evwheelguard filtered mouse
  --debug              Enable verbose wheel-event logs in journalctl
  --no-start           Install but do not start now
  --no-enable          Install but do not enable at boot
  --skip-packages      Do not install OS packages
  -h, --help           Show this help

After installation:
  systemctl status evwheelguard.service --no-pager
  journalctl -u evwheelguard.service -n 80 --no-pager
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO_URL="${2:?missing value for --repo}"; shift 2 ;;
    --branch) BRANCH="${2:?missing value for --branch}"; shift 2 ;;
    --install-dir) INSTALL_DIR="${2:?missing value for --install-dir}"; shift 2 ;;
    --device) DEVICE="${2:?missing value for --device}"; DEVICE_NAME=""; shift 2 ;;
    --device-name) DEVICE_NAME="${2:?missing value for --device-name}"; DEVICE=""; shift 2 ;;
    --lock-ms) LOCK_MS="${2:?missing value for --lock-ms}"; shift 2 ;;
    --scroll-mult) SCROLL_MULT="${2:?missing value for --scroll-mult}"; shift 2 ;;
    --name) OUTPUT_NAME="${2:?missing value for --name}"; shift 2 ;;
    --debug) DEBUG="1"; shift ;;
    --no-start) START_SERVICE="0"; shift ;;
    --no-enable) ENABLE_SERVICE="0"; shift ;;
    --skip-packages) SKIP_PACKAGES="1"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "Error: run this installer as root. Example:" >&2
  echo "  curl -fsSL https://raw.githubusercontent.com/YOUR_USERNAME/evwheelguard/main/install.sh | sudo bash" >&2
  exit 1
fi

if [[ "$REPO_URL" == *"YOUR_USERNAME"* ]]; then
  cat >&2 <<'EOF'
Error: install.sh still has the placeholder GitHub URL.

Maintainer fix before publishing:
  edit DEFAULT_REPO_URL in install.sh and replace YOUR_USERNAME with your GitHub username.

Temporary user workaround:
  pass --repo https://github.com/YOUR_USERNAME/evwheelguard.git
EOF
  exit 1
fi

if [[ -z "$DEVICE" && -z "$DEVICE_NAME" ]]; then
  echo "Error: set either --device or --device-name." >&2
  exit 1
fi

install_packages() {
  if [[ "$SKIP_PACKAGES" == "1" ]]; then
    echo "[evwheelguard] Skipping package installation."
    return 0
  fi

  echo "[evwheelguard] Installing dependencies..."
  if command -v dnf >/dev/null 2>&1; then
    dnf install -y git python3 python3-evdev
  elif command -v apt-get >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y git python3 python3-evdev
  elif command -v pacman >/dev/null 2>&1; then
    pacman -Sy --needed --noconfirm git python python-evdev
  elif command -v zypper >/dev/null 2>&1; then
    zypper --non-interactive install git python3 python3-evdev
  else
    echo "[evwheelguard] Could not detect package manager. Make sure git, python3, and python-evdev are installed."
  fi
}

shell_quote() {
  printf '%q' "$1"
}

write_config_var() {
  local key="$1"
  local value="$2"
  printf '%s=' "$key" >> /etc/evwheelguard/config
  shell_quote "$value" >> /etc/evwheelguard/config
  printf '\n' >> /etc/evwheelguard/config
}

install_packages

echo "[evwheelguard] Installing repository into $INSTALL_DIR..."
if [[ -d "$INSTALL_DIR/.git" ]]; then
  git -C "$INSTALL_DIR" fetch --all --prune
  git -C "$INSTALL_DIR" checkout "$BRANCH"
  git -C "$INSTALL_DIR" pull --ff-only
else
  rm -rf "$INSTALL_DIR"
  git clone --branch "$BRANCH" "$REPO_URL" "$INSTALL_DIR"
fi

echo "[evwheelguard] Installing command wrapper..."
SCRIPT_PATH="$INSTALL_DIR/src/evwheelguard/cli.py"
cat > /usr/local/bin/evwheelguard <<SH_WRAPPER
#!/usr/bin/env bash
SCRIPT_PATH=$(shell_quote "$SCRIPT_PATH")
exec /usr/bin/python3 "\$SCRIPT_PATH" "\$@"
SH_WRAPPER
chmod 0755 /usr/local/bin/evwheelguard

echo "[evwheelguard] Enabling uinput module..."
printf 'uinput\n' > /etc/modules-load.d/uinput.conf
modprobe uinput || true

mkdir -p /etc/evwheelguard
: > /etc/evwheelguard/config
write_config_var DEVICE "$DEVICE"
write_config_var DEVICE_NAME "$DEVICE_NAME"
write_config_var LOCK_MS "$LOCK_MS"
write_config_var SCROLL_MULT "$SCROLL_MULT"
write_config_var OUTPUT_NAME "$OUTPUT_NAME"
write_config_var DEBUG "$DEBUG"
chmod 0644 /etc/evwheelguard/config

echo "[evwheelguard] Installing service runner..."
cat > /usr/local/sbin/evwheelguard-service <<'SH_SERVICE_RUNNER'
#!/usr/bin/env bash
set -euo pipefail

CONFIG_FILE="/etc/evwheelguard/config"
if [[ ! -r "$CONFIG_FILE" ]]; then
  echo "Missing config: $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

args=()
if [[ -n "${DEVICE:-}" ]]; then
  args+=(--device "$DEVICE")
elif [[ -n "${DEVICE_NAME:-}" ]]; then
  args+=(--device-name "$DEVICE_NAME")
else
  echo "Set DEVICE or DEVICE_NAME in $CONFIG_FILE" >&2
  exit 1
fi

args+=(--lock-ms "${LOCK_MS:-140}")
args+=(--scroll-mult "${SCROLL_MULT:-1}")
args+=(--name "${OUTPUT_NAME:-evwheelguard filtered mouse}")

if [[ "${DEBUG:-0}" == "1" ]]; then
  args+=(--debug)
fi

exec /usr/local/bin/evwheelguard "${args[@]}"
SH_SERVICE_RUNNER
chmod 0755 /usr/local/sbin/evwheelguard-service

echo "[evwheelguard] Installing systemd service..."
cat > /etc/systemd/system/evwheelguard.service <<'SH_SYSTEMD'
[Unit]
Description=evwheelguard scroll-wheel stabilizer
Documentation=https://github.com/YOUR_USERNAME/evwheelguard
After=multi-user.target systemd-udev-settle.service
Wants=systemd-udev-settle.service

[Service]
Type=simple
ExecStart=/usr/local/sbin/evwheelguard-service
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
SH_SYSTEMD

# Replace placeholder in local unit docs if possible.
sed -i "s#https://github.com/YOUR_USERNAME/evwheelguard#$REPO_URL#g" /etc/systemd/system/evwheelguard.service || true

systemctl daemon-reload

if [[ "$ENABLE_SERVICE" == "1" ]]; then
  echo "[evwheelguard] Enabling service at boot..."
  systemctl enable evwheelguard.service
fi

if [[ "$START_SERVICE" == "1" ]]; then
  echo "[evwheelguard] Starting service..."
  systemctl restart evwheelguard.service
fi

cat <<EOF

[evwheelguard] Installed.

Config:
  /etc/evwheelguard/config

Commands:
  evwheelguard --list-devices
  systemctl status evwheelguard.service --no-pager
  journalctl -u evwheelguard.service -n 80 --no-pager

Current settings:
  DEVICE=$DEVICE
  DEVICE_NAME=$DEVICE_NAME
  LOCK_MS=$LOCK_MS
  SCROLL_MULT=$SCROLL_MULT
  OUTPUT_NAME=$OUTPUT_NAME

EOF

if [[ "$START_SERVICE" == "1" ]]; then
  systemctl status evwheelguard.service --no-pager || true
fi
