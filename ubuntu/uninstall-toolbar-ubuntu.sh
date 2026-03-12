#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run with sudo/root: sudo bash ./ubuntu/uninstall-toolbar-ubuntu.sh"
  exit 1
fi

target_user="${SUDO_USER:-${USER:-}}"
if [[ -z "$target_user" ]]; then
  echo "Unable to resolve target desktop user."
  exit 1
fi

target_home="$(getent passwd "$target_user" | cut -d: -f6)"
if [[ -z "$target_home" || ! -d "$target_home" ]]; then
  echo "Unable to resolve home directory for user '$target_user'."
  exit 1
fi

install_dir="$target_home/.local/share/wtl-share-net/toolbar"
autostart_file="$target_home/.config/autostart/wtl-share-toolbar.desktop"

pkill -u "$target_user" -f "share_toolbar.py" >/dev/null 2>&1 || true
rm -f "$autostart_file"
rm -rf "$install_dir"

echo "WTL Share Toolbar uninstalled from Ubuntu."
