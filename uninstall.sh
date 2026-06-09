#!/usr/bin/env bash
set -Eeuo pipefail

OUTPUT_DIR="${OUTPUT_DIR:-/root/sb-node}"

need_root() {
  if [ "$(id -u)" -ne 0 ]; then
    printf 'run as root: sudo bash uninstall.sh\n' >&2
    exit 1
  fi
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

need_root

if command_exists systemctl; then
  systemctl disable --now sing-box || true
  rm -f /etc/systemd/system/sing-box.service.d/10-sb-node.conf
  rmdir /etc/systemd/system/sing-box.service.d 2>/dev/null || true
  systemctl daemon-reload || true
fi

if command_exists apt-get; then
  apt-get remove -y sing-box || true
elif command_exists dnf; then
  dnf remove -y sing-box || true
elif command_exists yum; then
  yum remove -y sing-box || true
elif command_exists pacman; then
  pacman -Rns --noconfirm sing-box || true
elif command_exists apk; then
  apk del sing-box || true
fi

rm -rf /etc/sing-box
rm -rf "$OUTPUT_DIR"

printf 'sing-box uninstalled and config removed.\n'
