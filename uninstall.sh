#!/usr/bin/env bash
set -euo pipefail

REMOVE_REPO="1"

usage() {
  cat <<'EOF'
evwheelguard uninstaller

Usage:
  sudo ./uninstall.sh

Options:
  --keep-repo   Keep /opt/evwheelguard
  -h, --help    Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --keep-repo) REMOVE_REPO="0"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ "${EUID}" -ne 0 ]]; then
  echo "Error: run as root. Example: sudo ./uninstall.sh" >&2
  exit 1
fi

systemctl disable --now evwheelguard.service 2>/dev/null || true
rm -f /etc/systemd/system/evwheelguard.service
rm -f /usr/local/bin/evwheelguard
rm -f /usr/local/sbin/evwheelguard-service
rm -rf /etc/evwheelguard

if [[ "$REMOVE_REPO" == "1" ]]; then
  rm -rf /opt/evwheelguard
fi

systemctl daemon-reload

echo "evwheelguard removed."
