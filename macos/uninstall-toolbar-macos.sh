#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run with sudo/root: sudo bash ./macos/uninstall-toolbar-macos.sh"
  exit 1
fi

target_user="${SUDO_USER:-${USER:-}}"
if [[ -z "$target_user" ]]; then
  echo "Unable to resolve target desktop user."
  exit 1
fi

target_home="$(dscl . -read "/Users/$target_user" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
if [[ -z "$target_home" || ! -d "$target_home" ]]; then
  echo "Unable to resolve home directory for user '$target_user'."
  exit 1
fi

install_dir="$target_home/Library/Application Support/WTL-Share-Net/toolbar"
plist="$target_home/Library/LaunchAgents/com.wtl.sharetoolbar.plist"
uid="$(id -u "$target_user")"

launchctl bootout "gui/$uid" "$plist" >/dev/null 2>&1 || true
rm -f "$plist"
pkill -u "$target_user" -f "share_toolbar.py" >/dev/null 2>&1 || true
rm -rf "$install_dir"

echo "WTL Share Toolbar uninstalled from macOS."
