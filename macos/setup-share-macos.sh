#!/usr/bin/env bash
set -euo pipefail

share_name="Share-macOS"
share_path="/Users/Shared/Share-macOS"
smb_conf="/etc/smb.conf"
confirm_exposure=""
client_ip=""
share_user=""
share_pass=""

usage() {
  cat <<'EOF'
Usage:
  sudo bash ./macos/setup-share-macos.sh [options]

Options:
  --confirm-exposure          Non-interactive confirmation flag
  --client-ip <ip-or-cidr>    Allowed remote client IPv4 or CIDR scope
  --share-user <username>     Existing macOS local account allowed to access share
  --share-pass <password>     Password for share user (optional; prompted if omitted)
  --share-name <name>         Share name (default: Share-macOS)
  --share-path <path>         Share path (default: /Users/Shared/Share-macOS)
  -h, --help                  Show help

Notes:
  - Uses the existing macOS account password for SMB auth.
  - Does not create new macOS users.
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

mask_octet_to_bits() {
  case "$1" in
    255) echo 8 ;;
    254) echo 7 ;;
    252) echo 6 ;;
    248) echo 5 ;;
    240) echo 4 ;;
    224) echo 3 ;;
    192) echo 2 ;;
    128) echo 1 ;;
    0) echo 0 ;;
    *) echo -1 ;;
  esac
}

mask_to_prefix() {
  local mask="$1" bits=0
  IFS='.' read -r o1 o2 o3 o4 <<<"$mask"
  for octet in "$o1" "$o2" "$o3" "$o4"; do
    octet_bits="$(mask_octet_to_bits "$octet")"
    [[ "$octet_bits" -ge 0 ]] || return 1
    bits=$((bits + octet_bits))
  done
  echo "$bits"
}

detect_primary_cidr() {
  local iface ip mask prefix
  iface="$(route -n get default 2>/dev/null | awk '/interface:/{print $2; exit}')"
  [[ -n "$iface" ]] || return 1
  ip="$(ipconfig getifaddr "$iface" 2>/dev/null || true)"
  [[ -n "$ip" ]] || return 1
  mask="$(ipconfig getoption "$iface" subnet_mask 2>/dev/null || true)"
  if [[ -z "$mask" ]]; then
    mask="$(ifconfig "$iface" | awk '/inet / {for (i=1;i<=NF;i++) if ($i=="netmask") {print $(i+1); exit}}')"
    if [[ "$mask" == 0x* ]]; then
      # Convert hex mask to dotted decimal.
      hex="${mask#0x}"
      mask="$((16#${hex:0:2})).$((16#${hex:2:2})).$((16#${hex:4:2})).$((16#${hex:6:2}))"
    fi
  fi
  [[ -n "$mask" ]] || return 1
  prefix="$(mask_to_prefix "$mask")" || return 1
  echo "$ip/$prefix"
}

apply_system_preflight() {
  echo "Applying macOS system preflight"

  if [[ -x "/usr/libexec/ApplicationFirewall/socketfilterfw" ]]; then
    /usr/libexec/ApplicationFirewall/socketfilterfw --add /usr/sbin/smbd >/dev/null 2>&1 || true
    /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp /usr/sbin/smbd >/dev/null 2>&1 || true
  fi

  if command -v nordvpn >/dev/null 2>&1; then
    # NordVPN LAN restrictions can block local SMB traffic.
    nordvpn set lan-discovery on >/dev/null 2>&1 || true
    nordvpn set killswitch off >/dev/null 2>&1 || true
  fi
}

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

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "This installer is for macOS only."
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm-exposure)
      confirm_exposure="yes"
      shift
      ;;
    --client-ip)
      client_ip="${2:-}"
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
    --share-name)
      share_name="${2:-}"
      shift 2
      ;;
    --share-path)
      share_path="${2:-}"
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

echo "=== Share-macOS Setup ==="
echo "This script opens an SMB network share on this Mac."
echo "You are about to expose a network share and firewall scope on this Mac."
if [[ -z "$confirm_exposure" ]]; then
  read -r -p "Type YES to continue: " confirm_exposure
fi
if [[ "$confirm_exposure" != "yes" && "$confirm_exposure" != "YES" ]]; then
  echo "Confirmation not accepted."
  exit 1
fi

if [[ -z "$client_ip" ]]; then
  detected_scope="$(detect_primary_cidr || true)"
  if [[ -n "$detected_scope" ]]; then
    entered_scope=""
    read -r -p "Enter allowed remote client IP/CIDR (press Enter for auto: $detected_scope): " entered_scope
    client_ip="${entered_scope:-$detected_scope}"
  else
    client_ip="$(read_required "Enter allowed remote client IP/CIDR: ")"
  fi
fi
if [[ -z "$share_user" ]]; then
  share_user="$(read_required "Enter existing macOS username for SMB access: ")"
fi

if [[ -z "$share_pass" ]]; then
  read -r -s -p "Enter the NETWORK SHARE password (macOS account password) for '$share_user': " share_pass
  echo
  read -r -s -p "Confirm the NETWORK SHARE password: " share_pass_confirm
  echo
else
  share_pass_confirm="$share_pass"
fi

if ! is_valid_ipv4_or_cidr "$client_ip"; then
  echo "Invalid IPv4/CIDR value: $client_ip"
  exit 1
fi

if ! id "$share_user" >/dev/null 2>&1; then
  echo "Local user '$share_user' does not exist."
  exit 1
fi

if [[ "$share_pass" != "$share_pass_confirm" ]]; then
  echo "Passwords do not match."
  exit 1
fi

# Validate credentials up front so SMB login failures are caught during setup.
if ! dscl /Search -authonly "$share_user" "$share_pass" >/dev/null 2>&1; then
  echo "Credential validation failed for user '$share_user'."
  exit 1
fi

apply_system_preflight

echo "[1/6] Creating folder $share_path"
mkdir -p "$share_path"
chown -R "$share_user:staff" "$share_path"
chmod 0770 "$share_path"

echo "[2/6] Backing up smb.conf"
if [[ -f "$smb_conf" ]]; then
  cp "$smb_conf" "${smb_conf}.bak.$(date +%F-%H%M%S)"
else
  touch "$smb_conf"
fi

echo "[3/6] Rewriting share stanza [$share_name]"
tmp_file="$(mktemp)"
awk -v section="$share_name" '
  BEGIN { in_section=0 }
  $0 ~ "^\\[" section "\\]$" { in_section=1; next }
  /^\[/ && in_section { in_section=0 }
  !in_section { print }
' "$smb_conf" > "$tmp_file"
mv "$tmp_file" "$smb_conf"

cat >>"$smb_conf" <<EOF

[$share_name]
   path = $share_path
   browseable = yes
   read only = no
   guest ok = no
   valid users = $share_user
   create mask = 0660
   directory mask = 0770
   hosts allow = $client_ip 127.0.0.1 ::1
   hosts deny = 0.0.0.0/0
EOF

echo "[4/6] Enabling SMB service"
launchctl enable system/com.apple.smbd >/dev/null 2>&1 || true
launchctl kickstart -k system/com.apple.smbd

echo "[5/6] Ensuring user is in SMB access group"
dseditgroup -o edit -a "$share_user" -t user com.apple.access_smb >/dev/null 2>&1 || true

echo "[6/6] Validation"
if ! launchctl print system/com.apple.smbd >/dev/null 2>&1; then
  echo "Warning: SMB daemon status check failed."
fi

echo
echo "Share-macOS setup complete."
echo "Share path: $share_path"
echo "Share name: //$HOSTNAME/$share_name"
echo "Allowed client scope: $client_ip"
echo "SMB username: $share_user"
echo "SMB password: the password for '$share_user'."
