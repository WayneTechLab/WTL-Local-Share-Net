#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run with sudo/root: sudo bash ./ubuntu/install-toolbar-ubuntu.sh"
  exit 1
fi

target_user="${SUDO_USER:-${USER:-}}"
if [[ -z "$target_user" || "$target_user" == "root" ]]; then
  echo "Run this installer with sudo from the desktop user session."
  echo "Example: sudo bash ./ubuntu/install-toolbar-ubuntu.sh"
  exit 1
fi

target_home="$(getent passwd "$target_user" | cut -d: -f6)"
if [[ -z "$target_home" || ! -d "$target_home" ]]; then
  echo "Unable to resolve home directory for user '$target_user'."
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src_dir="$repo_root/toolbar"
install_dir="$target_home/.local/share/wtl-share-net/toolbar"
autostart_dir="$target_home/.config/autostart"
desktop_file="$autostart_dir/wtl-share-toolbar.desktop"
launcher="$install_dir/start-toolbar.sh"
config_file="$install_dir/config.json"
log_file="$install_dir/toolbar.log"

mkdir -p "$install_dir" "$autostart_dir" "$target_home/.local/bin"
cp "$src_dir/share_toolbar.py" "$install_dir/share_toolbar.py"
if [[ ! -f "$config_file" ]]; then
  cp "$src_dir/config.template.json" "$config_file"
fi

chown -R "$target_user:$target_user" "$target_home/.local"

if command -v apt-get >/dev/null 2>&1; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y \
    python3 python3-pip python3-gi \
    libayatana-appindicator3-1 gir1.2-ayatanaappindicator3-0.1 || true

  DEBIAN_FRONTEND=noninteractive apt-get install -y gir1.2-appindicator3-0.1 || true
fi

sudo -u "$target_user" python3 -m pip install --user --break-system-packages pystray pillow

cat >"$launcher" <<EOF
#!/usr/bin/env bash
exec python3 "$install_dir/share_toolbar.py" --config "$config_file" >>"$log_file" 2>&1
EOF
chmod +x "$launcher"

cat >"$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=WTL Share Toolbar
Comment=WTL share status and quick-open menu
Exec=$launcher
Terminal=false
X-GNOME-Autostart-enabled=true
X-GNOME-Autostart-Delay=5
EOF

sudo -u "$target_user" nohup "$launcher" >/dev/null 2>&1 &

chown -R "$target_user:$target_user" "$install_dir" "$autostart_dir"

echo "WTL Share Toolbar installed and set to autostart on Ubuntu."
echo "Config file: $config_file"
echo "Log file: $log_file"
