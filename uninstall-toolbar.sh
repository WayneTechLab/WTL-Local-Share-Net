#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
os_name="$(uname -s)"

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run with sudo/root: sudo bash ./uninstall-toolbar.sh"
  exit 1
fi

case "$os_name" in
  Linux)
    exec bash "$root_dir/ubuntu/uninstall-toolbar-ubuntu.sh" "$@"
    ;;
  Darwin)
    exec bash "$root_dir/macos/uninstall-toolbar-macos.sh" "$@"
    ;;
  *)
    echo "Unsupported OS: $os_name"
    echo "On Windows, run windows/uninstall-toolbar-windows.ps1"
    exit 1
    ;;
esac
