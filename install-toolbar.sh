#!/usr/bin/env bash
set -euo pipefail

root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
os_name="$(uname -s)"
args=("$@")

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run with sudo/root: sudo bash ./install-toolbar.sh"
  exit 1
fi

case "$os_name" in
  Linux)
    exec bash "$root_dir/ubuntu/install-toolbar-ubuntu.sh" "${args[@]}"
    ;;
  Darwin)
    exec bash "$root_dir/macos/install-toolbar-macos.sh" "${args[@]}"
    ;;
  *)
    echo "Unsupported OS: $os_name"
    echo "On Windows, run windows/install-toolbar-windows.ps1"
    exit 1
    ;;
esac
