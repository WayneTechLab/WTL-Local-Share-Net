#!/usr/bin/env bash
set -euo pipefail

windows_ip=""
share_name="Share-Windows"
mount_point="/mnt/share-windows"
username=""
domain=""
smb_version="3.1.1"
use_seal="true"
password=""

usage() {
  cat <<'EOF'
Usage:
  sudo bash ./ubuntu/mount-share-windows.sh [options]

Options:
  --windows-ip <ip>      Windows host IP (prompted if omitted)
  --share-name <name>    Share name (default: Share-Windows)
  --mount-point <path>   Local mount path (default: /mnt/share-windows)
  --username <user>      Windows username (prompted if omitted)
  --domain <domain>      Windows domain/machine name (prompted if omitted)
  --smb-version <ver>    SMB protocol version (default: 3.1.1)
  --no-seal              Disable SMB encryption (seal)
  --password <pass>      Password (not recommended; visible in shell history)
  -h, --help             Show help

If --password is not provided, the script prompts securely.
EOF
}

is_valid_ipv4() {
  local ip="$1"
  local -a octets
  IFS='.' read -r -a octets <<<"$ip"
  [[ ${#octets[@]} -eq 4 ]] || return 1
  for octet in "${octets[@]}"; do
    [[ "$octet" =~ ^[0-9]+$ ]] || return 1
    ((octet >= 0 && octet <= 255)) || return 1
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --windows-ip)
      windows_ip="${2:-}"
      shift 2
      ;;
    --share-name)
      share_name="${2:-}"
      shift 2
      ;;
    --mount-point)
      mount_point="${2:-}"
      shift 2
      ;;
    --username)
      username="${2:-}"
      shift 2
      ;;
    --domain)
      domain="${2:-}"
      shift 2
      ;;
    --smb-version)
      smb_version="${2:-}"
      shift 2
      ;;
    --no-seal)
      use_seal="false"
      shift
      ;;
    --password)
      password="${2:-}"
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

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo or as root."
  exit 1
fi

if [[ -z "$windows_ip" ]]; then
  read -r -p "Enter Windows host IP: " windows_ip
fi

if [[ -z "$username" ]]; then
  read -r -p "Enter Windows username: " username
fi

if [[ -z "$domain" ]]; then
  read -r -p "Enter Windows domain/machine name: " domain
fi

if [[ -z "$share_name" || -z "$mount_point" || -z "$smb_version" || -z "$windows_ip" || -z "$username" || -z "$domain" ]]; then
  echo "Required values are missing."
  usage
  exit 1
fi

if ! is_valid_ipv4 "$windows_ip"; then
  echo "Invalid IPv4 address: $windows_ip"
  exit 1
fi

if [[ -z "$password" ]]; then
  read -r -s -p "Enter Windows share password for ${domain}\\${username}: " password
  echo
fi

mkdir -p "$mount_point"

cred_file="$(mktemp)"
chmod 600 "$cred_file"
cat >"$cred_file" <<EOF
username=$username
password=$password
domain=$domain
EOF

trap 'rm -f "$cred_file"' EXIT

mount_opts="credentials=$cred_file,vers=$smb_version"
if [[ "$use_seal" == "true" ]]; then
  mount_opts+=",seal"
fi

echo "Mounting //$windows_ip/$share_name to $mount_point"
if ! timeout 3 bash -c ">/dev/tcp/$windows_ip/445" 2>/dev/null; then
  echo "Cannot reach $windows_ip on TCP 445."
  echo "Checks:"
  echo "  1) Confirm Windows is powered on and on the same LAN."
  echo "  2) Confirm the current Windows IPv4 address matches $windows_ip."
  echo "  3) Confirm the Windows share is enabled and firewall allows this Linux host."
  exit 1
fi

mount -t cifs "//$windows_ip/$share_name" "$mount_point" -o "$mount_opts"
echo "Mounted successfully at $mount_point"
