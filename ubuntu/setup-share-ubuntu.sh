#!/usr/bin/env bash
set -euo pipefail

share_path="/Share-Ubuntu"
share_name="Share-Ubuntu"
samba_conf="/etc/samba/smb.conf"
share_conf_dir="/etc/samba/smb.conf.d"
share_conf_file="$share_conf_dir/wtl-local-share-net.conf"
confirm_exposure=""
allow_vpn_route="false"
windows_ip=""
share_user=""
share_pass=""
client_scope=""

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

is_valid_username() {
  local username="$1"
  [[ "$username" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

read_required() {
  local prompt="$1"
  local value=""
  while [[ -z "$value" ]]; do
    read -r -p "$prompt" value
  done
  printf '%s' "$value"
}

ensure_samba_include() {
  local include_line="   include = $share_conf_dir/*.conf"
  local tmp_file

  if grep -Eq "^[[:space:]]*include[[:space:]]*=[[:space:]]*$share_conf_dir/\\*\\.conf[[:space:]]*$" "$samba_conf"; then
    return 0
  fi

  tmp_file="$(mktemp)"
  cp "$samba_conf" "${samba_conf}.bak.$(date +%F-%H%M%S)"

  awk -v include_line="$include_line" '
    BEGIN { added=0 }
    /^\[global\][[:space:]]*$/ {
      print
      if (!added) {
        print include_line
        added=1
      }
      next
    }
    { print }
    END {
      if (!added) {
        print ""
        print "[global]"
        print include_line
      }
    }
  ' "$samba_conf" > "$tmp_file"

  mv "$tmp_file" "$samba_conf"
}

apply_system_preflight() {
  echo "Applying Ubuntu system preflight"

  if command -v nordvpn >/dev/null 2>&1; then
    # NordVPN LAN restrictions are a common reason SMB appears broken.
    nordvpn set lan-discovery on >/dev/null 2>&1 || true
    nordvpn set killswitch off >/dev/null 2>&1 || true
  fi
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
    --allow-vpn-route)
      allow_vpn_route="true"
      shift
      ;;
    --windows-ip)
      windows_ip="${2:-}"
      shift 2
      ;;
    --client-scope)
      client_scope="${2:-}"
      shift 2
      ;;
    --share-user)
      share_user="${2:-}"
      shift 2
      ;;
    --share-pass)
      share_pass="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1"
      exit 1
      ;;
  esac
done

echo "=== Share-Ubuntu Setup ==="
echo "This script opens an SMB network share on this computer."
echo "You are about to expose a network share and firewall scope on this machine."
if [[ -z "$confirm_exposure" ]]; then
  read -r -p "Type YES to continue: " confirm_exposure
fi
if [[ "$confirm_exposure" != "yes" && "$confirm_exposure" != "YES" ]]; then
  echo "Confirmation not accepted."
  exit 1
fi

if [[ -z "$windows_ip" ]]; then
  if [[ -n "$client_scope" ]]; then
    windows_ip="$client_scope"
  else
    detected_scope="$(detect_primary_cidr || true)"
    if [[ -n "$detected_scope" ]]; then
      entered_scope=""
      read -r -p "Enter allowed client IP/CIDR (press Enter for auto: $detected_scope): " entered_scope
      windows_ip="${entered_scope:-$detected_scope}"
    else
      windows_ip="$(read_required "Enter allowed client IP/CIDR: ")"
    fi
  fi
fi
if [[ -z "$share_user" ]]; then
  share_user="$(read_required "Enter the Linux username Windows will use: ")"
fi

if [[ -z "$share_pass" ]]; then
  read -r -s -p "Enter the password for this share user: " share_pass
  echo
  read -r -s -p "Confirm the password: " share_pass_confirm
  echo
else
  share_pass_confirm="$share_pass"
fi

if ! is_valid_ipv4_or_cidr "$windows_ip"; then
  echo "Invalid IPv4/CIDR value: $windows_ip"
  exit 1
fi

if ! is_valid_username "$share_user"; then
  echo "Invalid Linux username: $share_user"
  echo "Use lowercase letters, numbers, underscore, and dash."
  exit 1
fi

if [[ "$share_pass" != "$share_pass_confirm" ]]; then
  echo "Passwords do not match."
  exit 1
fi

apply_system_preflight

route_target="${windows_ip%/*}"
route_dev="$(ip route get "$route_target" 2>/dev/null | awk '{for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"
if [[ -n "$route_dev" && "$allow_vpn_route" != "true" ]]; then
  if [[ "$route_dev" =~ ^(nordtun|tun[0-9]*|wg[0-9]*|ppp[0-9]*)$ ]]; then
    echo "Client scope target $windows_ip is currently routed via '$route_dev' (VPN/tunnel)."
    echo "SMB validation/mount will likely fail until LAN routing is used."
    echo "Fix route first or rerun with --allow-vpn-route to continue anyway."
    exit 1
  fi
fi

echo "[1/8] Installing packages"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y samba smbclient cifs-utils ufw

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
ensure_samba_include

cat >"$share_conf_file" <<EOF
[$share_name]
   path = $share_path
   browseable = yes
   read only = no
   guest ok = no
   valid users = $share_user
   force user = $share_user
   create mask = 0660
   directory mask = 0770
   hosts allow = $windows_ip 127.0.0.1 ::1
   hosts deny = 0.0.0.0/0
EOF

echo "[7/8] Validating and restarting Samba"
testparm -s >/dev/null
systemctl enable smbd
systemctl restart smbd

echo "[8/8] Restricting firewall to $windows_ip"
while ufw status numbered | grep -q "445/tcp"; do
  rule_number="$(ufw status numbered | awk '/445\/tcp/ {gsub(/\[|\]/, "", $1); print $1; exit}')"
  [[ -n "$rule_number" ]] || break
  yes | ufw delete "$rule_number" >/dev/null
done
ufw allow from "$windows_ip" to any port 445 proto tcp comment "WTL-Local-Share-Net allow client scope"
ufw deny 445/tcp comment "WTL-Local-Share-Net deny others"
ufw --force enable

echo
echo "Share-Ubuntu setup complete."
echo "Folder: $share_path"
echo "SMB path: //$HOSTNAME/$share_name"
echo "Allowed client scope: $windows_ip"
echo "Share username: $share_user"
echo "From Windows, map with:"
echo "  net use Z: \\\\$(hostname -s)\\$share_name /user:$share_user"
