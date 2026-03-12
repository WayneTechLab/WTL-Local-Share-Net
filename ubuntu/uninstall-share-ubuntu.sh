#!/usr/bin/env bash
set -euo pipefail

share_name="Share-Ubuntu"
samba_conf="/etc/samba/smb.conf"
share_conf_file="/etc/samba/smb.conf.d/wtl-local-share-net.conf"
global_conf_file="/etc/samba/smb.conf.d/wtl-local-share-net-global.conf"
confirm_exposure=""
share_user=""
keep_user="false"

read_required() {
  local prompt="$1"
  local value=""
  while [[ -z "$value" ]]; do
    read -r -p "$prompt" value
  done
  printf '%s' "$value"
}

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo or as root."
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm-exposure)
      confirm_exposure="yes"
      shift
      ;;
    --share-user)
      share_user="${2:-}"
      shift 2
      ;;
    --keep-user)
      keep_user="true"
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

echo "=== Share-Ubuntu Uninstall ==="
echo "This script removes the Ubuntu share configuration created by this project."
echo "This will remove share configuration and firewall rules."
if [[ -z "$confirm_exposure" ]]; then
  read -r -p "Type YES to continue: " confirm_exposure
fi
if [[ "$confirm_exposure" != "yes" && "$confirm_exposure" != "YES" ]]; then
  echo "Confirmation not accepted."
  exit 1
fi

if [[ -z "$share_user" && -f "$share_conf_file" ]]; then
  share_user="$(awk -F= '/^[[:space:]]*valid users[[:space:]]*=/{gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); split($2, a, /[[:space:],]+/); print a[1]; exit}' "$share_conf_file")"
fi

if [[ -z "$share_user" && "$keep_user" != "true" ]]; then
  share_user="$(read_required "Enter the share user to remove (or press Ctrl+C): ")"
fi

if [[ "$keep_user" != "true" && -n "$share_user" ]]; then
  echo "[1/4] Disabling Samba user if present"
  if pdbedit -L | cut -d: -f1 | grep -Fxq "$share_user"; then
    smbpasswd -x "$share_user" >/dev/null
  fi

  echo "[2/4] Removing Linux user if present"
  if id "$share_user" >/dev/null 2>&1; then
    userdel "$share_user"
  fi
else
  echo "[1/4] Keeping local/Samba user (--keep-user or no user resolved)"
fi

echo "[3/4] Removing UFW SMB rules"
for pattern in "445/tcp" "139/tcp" "137/udp" "138/udp"; do
  while ufw status numbered | grep -q "$pattern"; do
    rule_number="$(ufw status numbered | awk -v p="$pattern" '$0 ~ p {gsub(/\[|\]/, "", $1); print $1; exit}')"
    [[ -n "$rule_number" ]] || break
    yes | ufw delete "$rule_number" >/dev/null
  done
done

echo "[4/4] Restarting Samba"
if [[ -f "$share_conf_file" ]]; then
  rm -f "$share_conf_file"
fi
if [[ -f "$global_conf_file" ]]; then
  rm -f "$global_conf_file"
fi
systemctl restart smbd || true

echo "Ubuntu share uninstall complete."
echo "Removed share definition [$share_name] from $share_conf_file."
