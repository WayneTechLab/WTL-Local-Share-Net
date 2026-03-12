#!/usr/bin/env bash
set -euo pipefail

share_name="Share-macOS"
smb_conf="/etc/smb.conf"
confirm_exposure=""

usage() {
  cat <<'EOF'
Usage:
  sudo bash ./macos/uninstall-share-macos.sh [options]

Options:
  --confirm-exposure          Non-interactive confirmation flag
  --share-name <name>         Share name to remove (default: Share-macOS)
  -h, --help                  Show help
EOF
}

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo or as root."
  exit 1
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This uninstaller is for macOS only."
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm-exposure)
      confirm_exposure="yes"
      shift
      ;;
    --share-name)
      share_name="${2:-}"
      shift 2
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

echo "=== Share-macOS Uninstall ==="
echo "This script removes the macOS SMB share configuration from /etc/smb.conf."
echo "This will remove share configuration."
if [[ -z "$confirm_exposure" ]]; then
  read -r -p "Type YES to continue: " confirm_exposure
fi
if [[ "$confirm_exposure" != "yes" && "$confirm_exposure" != "YES" ]]; then
  echo "Confirmation not accepted."
  exit 1
fi

if [[ -f "$smb_conf" ]]; then
  cp "$smb_conf" "${smb_conf}.bak.remove.$(date +%F-%H%M%S)"
  tmp_file="$(mktemp)"
  awk -v section="$share_name" '
    BEGIN { in_section=0 }
    $0 ~ "^\\[" section "\\]$" { in_section=1; next }
    /^\[/ && in_section { in_section=0 }
    !in_section { print }
  ' "$smb_conf" > "$tmp_file"
  mv "$tmp_file" "$smb_conf"
fi

launchctl kickstart -k system/com.apple.smbd >/dev/null 2>&1 || true

echo "Share stanza [$share_name] removed from $smb_conf."
echo "Folder data was not deleted."
