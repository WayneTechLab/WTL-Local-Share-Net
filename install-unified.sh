#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
detected_os=""
selected_os=""
mode="clean-reinstall"

usage() {
  cat <<'EOF'
Usage:
  bash ./install-unified.sh [options]

Options:
  --os <ubuntu|macos>                                           Override OS selection (auto-detect by default)
  --mode <clean-reinstall|install-only|update-app-only|share-only|toolbar-only|uninstall-only>
                                                                Install mode (default: clean-reinstall)
  --no-prompt                                                   Do not ask for confirmation
  -h, --help                                                    Show help

Behavior:
  - By default runs clean reinstall: uninstall then install.
  - Runs share setup for detected/selected OS.
  - Installs toolbar and configures autostart.
EOF
}

no_prompt="false"

legacy_cleanup() {
  local os="$1"

  pkill -f "share_toolbar.py" >/dev/null 2>&1 || true

  if [[ "$os" == "ubuntu" ]]; then
    rm -rf /root/.local/share/wtl-share-net/toolbar || true
    rm -f /root/.config/autostart/wtl-share-toolbar.desktop || true
    rm -f /etc/xdg/autostart/wtl-share-toolbar.desktop || true
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
      user_home="$(getent passwd "$SUDO_USER" | cut -d: -f6)"
      rm -rf "$user_home/.local/share/wtl-share-net/toolbar" || true
      rm -f "$user_home/.config/autostart/wtl-share-toolbar.desktop" || true
      rm -f "$user_home/.config/autostart/WTL Share Toolbar.desktop" || true
    fi
  elif [[ "$os" == "macos" ]]; then
    rm -rf "/Library/Application Support/WTL-Share-Net/toolbar" || true
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
      user_home="$(dscl . -read "/Users/$SUDO_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
      if [[ -n "$user_home" ]]; then
        rm -rf "$user_home/Library/Application Support/WTL-Share-Net/toolbar" || true
        rm -f "$user_home/Library/LaunchAgents/com.wtl.sharetoolbar.plist" || true
      fi
    fi
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --os)
      selected_os="${2:-}"
      shift 2
      ;;
    --mode)
      mode="${2:-}"
      shift 2
      ;;
    --no-prompt)
      no_prompt="true"
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

case "$mode" in
  clean-reinstall|install-only|update-app-only|share-only|toolbar-only|uninstall-only) ;;
  *)
    echo "Invalid --mode value: $mode"
    exit 1
    ;;
esac

if [[ "$selected_os" != "$detected_os" ]]; then
  echo "Selected OS '$selected_os' does not match current host '$detected_os'."
  echo "Run this installer on the target OS machine."
  exit 1
fi

if [[ "$no_prompt" != "true" ]]; then
  read -r -p "Detected OS: $selected_os. Proceed with mode '$mode'? [Y/n]: " confirm
  if [[ "${confirm:-Y}" =~ ^[Nn]$ ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

if [[ "$selected_os" == "ubuntu" ]]; then
  if [[ "$mode" == "clean-reinstall" || "$mode" == "update-app-only" || "$mode" == "uninstall-only" ]]; then
    legacy_cleanup "$selected_os"
  fi

  if [[ "$mode" == "clean-reinstall" || "$mode" == "uninstall-only" ]]; then
    sudo bash "$repo_root/ubuntu/uninstall-share-ubuntu.sh" --confirm-exposure --keep-user || true
  fi

  if [[ "$mode" == "clean-reinstall" || "$mode" == "update-app-only" || "$mode" == "uninstall-only" ]]; then
    sudo bash "$repo_root/ubuntu/uninstall-toolbar-ubuntu.sh" || true
  fi

  if [[ "$mode" == "uninstall-only" ]]; then
    echo "Unified uninstall complete for $selected_os."
    exit 0
  fi

  if [[ "$mode" == "clean-reinstall" || "$mode" == "install-only" || "$mode" == "share-only" ]]; then
    sudo bash "$repo_root/ubuntu/setup-share-ubuntu.sh" --confirm-exposure
  fi
  if [[ "$mode" == "clean-reinstall" || "$mode" == "install-only" || "$mode" == "update-app-only" || "$mode" == "toolbar-only" ]]; then
    sudo bash "$repo_root/install-toolbar.sh" --no-prompt
  fi
elif [[ "$selected_os" == "macos" ]]; then
  if [[ "$mode" == "clean-reinstall" || "$mode" == "update-app-only" || "$mode" == "uninstall-only" ]]; then
    legacy_cleanup "$selected_os"
  fi

  if [[ "$mode" == "clean-reinstall" || "$mode" == "uninstall-only" ]]; then
    sudo bash "$repo_root/macos/uninstall-share-macos.sh" --confirm-exposure || true
  fi

  if [[ "$mode" == "clean-reinstall" || "$mode" == "update-app-only" || "$mode" == "uninstall-only" ]]; then
    sudo bash "$repo_root/macos/uninstall-toolbar-macos.sh" || true
  fi

  if [[ "$mode" == "uninstall-only" ]]; then
    echo "Unified uninstall complete for $selected_os."
    exit 0
  fi

  if [[ "$mode" == "clean-reinstall" || "$mode" == "install-only" || "$mode" == "share-only" ]]; then
    sudo bash "$repo_root/macos/setup-share-macos.sh" --confirm-exposure
  fi
  if [[ "$mode" == "clean-reinstall" || "$mode" == "install-only" || "$mode" == "update-app-only" || "$mode" == "toolbar-only" ]]; then
    sudo bash "$repo_root/install-toolbar.sh" --no-prompt
  fi
fi

echo "Unified '$mode' complete for $selected_os."
