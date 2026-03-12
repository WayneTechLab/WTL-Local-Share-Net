#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
detected_os=""
selected_os=""

usage() {
  cat <<'EOF'
Usage:
  bash ./install-unified.sh [options]

Options:
  --os <ubuntu|macos>   Override OS selection (auto-detect by default)
  --no-prompt           Do not ask for confirmation
  --skip-clean          Skip uninstall phase and run install only
  -h, --help            Show help

Behavior:
  - By default runs clean reinstall: uninstall then install.
  - Runs share setup for detected/selected OS.
  - Installs toolbar and configures autostart.
EOF
}

no_prompt="false"
skip_clean="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --os)
      selected_os="${2:-}"
      shift 2
      ;;
    --no-prompt)
      no_prompt="true"
      shift
      ;;
    --skip-clean)
      skip_clean="true"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1"
      usage
      exit 1
      ;;
  esac
done

case "$(uname -s)" in
  Linux) detected_os="ubuntu" ;;
  Darwin) detected_os="macos" ;;
  *)
    echo "Unsupported OS for shell installer: $(uname -s)"
    echo "On Windows use: .\\install-unified.ps1"
    exit 1
    ;;
esac

if [[ -z "$selected_os" ]]; then
  selected_os="$detected_os"
fi

if [[ "$selected_os" != "ubuntu" && "$selected_os" != "macos" ]]; then
  echo "Invalid --os value: $selected_os"
  exit 1
fi

if [[ "$selected_os" != "$detected_os" ]]; then
  echo "Selected OS '$selected_os' does not match current host '$detected_os'."
  echo "Run this installer on the target OS machine."
  exit 1
fi

if [[ "$no_prompt" != "true" ]]; then
  mode="clean reinstall (uninstall then install)"
  if [[ "$skip_clean" == "true" ]]; then
    mode="install only"
  fi
  read -r -p "Detected OS: $selected_os. Proceed with $mode? [Y/n]: " confirm
  if [[ "${confirm:-Y}" =~ ^[Nn]$ ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

if [[ "$selected_os" == "ubuntu" ]]; then
  if [[ "$skip_clean" != "true" ]]; then
    sudo bash "$repo_root/ubuntu/uninstall-toolbar-ubuntu.sh" || true
    sudo bash "$repo_root/ubuntu/uninstall-share-ubuntu.sh" --confirm-exposure --keep-user || true
  fi
  sudo bash "$repo_root/ubuntu/setup-share-ubuntu.sh" --confirm-exposure
  sudo bash "$repo_root/install-toolbar.sh" --no-prompt
elif [[ "$selected_os" == "macos" ]]; then
  if [[ "$skip_clean" != "true" ]]; then
    sudo bash "$repo_root/macos/uninstall-toolbar-macos.sh" || true
    sudo bash "$repo_root/macos/uninstall-share-macos.sh" --confirm-exposure || true
  fi
  sudo bash "$repo_root/macos/setup-share-macos.sh" --confirm-exposure
  sudo bash "$repo_root/install-toolbar.sh" --no-prompt
fi

echo "Unified install complete for $selected_os."
