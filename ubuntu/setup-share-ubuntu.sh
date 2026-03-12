#!/usr/bin/env bash
set -euo pipefail

required_setup_passphrase="WTL-SETUP-2026"
share_path="/Share-Ubuntu"
share_name="Share-Ubuntu"
samba_conf="/etc/samba/smb.conf"
share_conf_dir="/etc/samba/smb.conf.d"
share_conf_file="$share_conf_dir/wtl-local-share-net.conf"

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

echo "=== Share-Ubuntu Setup ==="
read -r -s -p "Enter setup passphrase: " entered_passphrase
echo
if [[ "$entered_passphrase" != "$required_setup_passphrase" ]]; then
  echo "Invalid setup passphrase."
  exit 1
fi

windows_ip="$(read_required "Enter Windows machine IP: ")"
share_user="$(read_required "Enter the Linux username Windows will use: ")"
read -r -s -p "Enter the password for this share user: " share_pass
echo
read -r -s -p "Confirm the password: " share_pass_confirm
echo

if [[ "$share_pass" != "$share_pass_confirm" ]]; then
  echo "Passwords do not match."
  exit 1
fi

echo "[1/8] Installing packages"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y samba smbclient ufw

echo "[2/8] Creating folder $share_path"
mkdir -p "$share_path"

echo "[3/8] Creating or updating restricted user $share_user"
if ! id "$share_user" >/dev/null 2>&1; then
  useradd -M -s /usr/sbin/nologin "$share_user"
fi
echo "$share_user:$share_pass" | chpasswd

echo "[4/8] Setting folder permissions"
chown -R "$share_user:$share_user" "$share_path"
chmod 0770 "$share_path"

echo "[5/8] Setting Samba password"
(echo "$share_pass"; echo "$share_pass") | smbpasswd -a -s "$share_user" >/dev/null
smbpasswd -e "$share_user" >/dev/null

echo "[6/8] Writing Samba configuration"
mkdir -p "$share_conf_dir"
if ! grep -Fqx "include = $share_conf_dir/*.conf" "$samba_conf"; then
  cp "$samba_conf" "${samba_conf}.bak.$(date +%F-%H%M%S)"
  cat >>"$samba_conf" <<EOF

include = $share_conf_dir/*.conf
EOF
fi

cat >"$share_conf_file" <<EOF
[global]
   map to guest = never
   smb encrypt = required
   server min protocol = SMB3
   disable netbios = yes
   log file = /var/log/samba/log.%m
   max log size = 1000

[$share_name]
   path = $share_path
   browseable = yes
   read only = no
   guest ok = no
   valid users = $share_user
   force user = $share_user
   create mask = 0660
   directory mask = 0770
   hosts allow = $windows_ip 127.0.0.1
   hosts deny = 0.0.0.0/0
EOF

echo "[7/8] Restarting Samba"
systemctl enable smbd
systemctl restart smbd

echo "[8/8] Restricting firewall to $windows_ip"
ufw allow from "$windows_ip" to any port 445 proto tcp
ufw deny 445/tcp || true
ufw --force enable

echo
echo "Share-Ubuntu setup complete."
echo "Folder: $share_path"
echo "SMB path: //$HOSTNAME/$share_name"
echo "Allowed remote IP: $windows_ip"
echo "Share username: $share_user"
