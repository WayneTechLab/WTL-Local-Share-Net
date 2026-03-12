#!/usr/bin/env bash
set -euo pipefail

windows_ip=""
share_user="shareuser"
share_path="/Share-Ubuntu"
share_name="Share-Ubuntu"
samba_conf="/etc/samba/smb.conf"
share_conf_dir="/etc/samba/smb.conf.d"
share_conf_file="$share_conf_dir/wtl-local-share-net.conf"
global_conf_file="$share_conf_dir/wtl-local-share-net-global.conf"

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

is_valid_ipv4_or_cidr() {
  local value="$1"
  if [[ "$value" == */* ]]; then
    local ip="${value%/*}"
    local prefix="${value#*/}"
    is_valid_ipv4 "$ip" || return 1
    [[ "$prefix" =~ ^[0-9]+$ ]] || return 1
    ((prefix >= 0 && prefix <= 32)) || return 1
    return 0
  fi
  is_valid_ipv4 "$value"
}

detect_primary_cidr() {
  local dev cidr
  dev="$(ip route show default 2>/dev/null | awk '/default/ {for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"
  [[ -n "$dev" ]] || return 1
  cidr="$(ip -4 addr show dev "$dev" | awk '/inet / {print $2; exit}')"
  [[ -n "$cidr" ]] || return 1
  printf '%s' "$cidr"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --windows-ip)
      windows_ip="${2:-}"
      shift 2
      ;;
    --share-user)
      share_user="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

if [[ -z "$windows_ip" ]]; then
  windows_ip="$(detect_primary_cidr || true)"
fi

if [[ -z "$windows_ip" ]]; then
  echo "Unable to auto-detect client scope. Use --windows-ip <ip-or-cidr>."
  exit 1
fi

if ! is_valid_ipv4_or_cidr "$windows_ip"; then
  echo "Invalid IPv4/CIDR value: $windows_ip"
  exit 1
fi

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run this script with sudo or as root."
  exit 1
fi

echo "[1/8] Backing up smb.conf"
cp "$samba_conf" "${samba_conf}.repair-bak.$(date +%F-%H%M%S)"

echo "[2/8] Ensuring include directory"
mkdir -p "$share_conf_dir"

echo "[3/8] Resetting include line"
sed -i '\|^[[:space:]]*include[[:space:]]*=.*smb\.conf\.d/\*\.conf[[:space:]]*$|d' "$samba_conf"
if grep -q '^\[global\]$' "$samba_conf"; then
  sed -i '/^\[global\]$/a\   include = /etc/samba/smb.conf.d/*.conf' "$samba_conf"
else
  cat >>"$samba_conf" <<EOF

[global]
   include = /etc/samba/smb.conf.d/*.conf
EOF
fi

echo "[4/8] Writing Share-Ubuntu snippet"
cat >"$global_conf_file" <<EOF
[global]
   map to guest = Never
   server min protocol = SMB2_10
   server signing = mandatory
   ntlm auth = ntlmv2-only
EOF

cat >"$share_conf_file" <<EOF
[$share_name]
   path = $share_path
   browseable = yes
   read only = no
   guest ok = no
   smb encrypt = desired
   valid users = $share_user
   force user = $share_user
   create mask = 0660
   directory mask = 0770
   hosts allow = $windows_ip 127.0.0.1 ::1
   hosts deny = 0.0.0.0/0
EOF

echo "[5/8] Ensuring share path permissions"
mkdir -p "$share_path"
chown -R "$share_user:$share_user" "$share_path"
chmod 0770 "$share_path"

echo "[6/8] Rebuilding SMB firewall rules"
if command -v ufw >/dev/null 2>&1; then
  ufw allow from "$windows_ip" to any port 445 proto tcp
  ufw allow from "$windows_ip" to any port 139 proto tcp
  ufw allow from "$windows_ip" to any port 137 proto udp
  ufw allow from "$windows_ip" to any port 138 proto udp
  ufw deny 445/tcp || true
  ufw --force enable
fi

echo "[7/8] Validating Samba config"
testparm -s >/dev/null

echo "[8/8] Restarting Samba"
systemctl restart smbd
systemctl is-active smbd

echo "Repair complete."
echo "If authentication fails, reset Samba password:"
echo "  sudo smbpasswd -a $share_user"
echo "  sudo smbpasswd -e $share_user"
