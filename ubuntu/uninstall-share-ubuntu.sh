#!/usr/bin/env bash
set -euo pipefail

required_setup_passphrase="WTL-SETUP-2026"
share_name="Share-Ubuntu"
samba_conf="/etc/samba/smb.conf"
share_conf_file="/etc/samba/smb.conf.d/wtl-local-share-net.conf"

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

echo "=== Share-Ubuntu Uninstall ==="
read -r -s -p "Enter setup passphrase: " entered_passphrase
echo
if [[ "$entered_passphrase" != "$required_setup_passphrase" ]]; then
  echo "Invalid setup passphrase."
  exit 1
fi

share_user="$(read_required "Enter the share user to remove: ")"

echo "[1/4] Disabling Samba user if present"
if pdbedit -L | cut -d: -f1 | grep -Fxq "$share_user"; then
  smbpasswd -x "$share_user" >/dev/null
fi

echo "[2/4] Removing Linux user if present"
if id "$share_user" >/dev/null 2>&1; then
  userdel "$share_user"
fi

echo "[3/4] Removing UFW SMB rules"
while ufw status numbered | grep -q "445/tcp"; do
  rule_number="$(ufw status numbered | awk '/445\/tcp/ {gsub(/\[|\]/, "", $1); print $1; exit}')"
  [[ -n "$rule_number" ]] || break
  yes | ufw delete "$rule_number" >/dev/null
done

echo "[4/4] Restarting Samba"
if [[ -f "$share_conf_file" ]]; then
  rm -f "$share_conf_file"
fi
systemctl restart smbd || true

echo "Ubuntu share uninstall complete."
echo "Removed share definition [$share_name] from $share_conf_file."
