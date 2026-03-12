#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -ne 0 ]]; then
  echo "Run with sudo/root: sudo bash ./macos/install-toolbar-macos.sh"
  exit 1
fi

target_user="${SUDO_USER:-${USER:-}}"
if [[ -z "$target_user" ]]; then
  echo "Unable to resolve target desktop user."
  exit 1
fi

target_home="$(dscl . -read "/Users/$target_user" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
if [[ -z "$target_home" || ! -d "$target_home" ]]; then
  echo "Unable to resolve home directory for user '$target_user'."
  exit 1
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src_dir="$repo_root/toolbar"
install_dir="$target_home/Library/Application Support/WTL-Share-Net/toolbar"
launch_agents_dir="$target_home/Library/LaunchAgents"
plist="$launch_agents_dir/com.wtl.sharetoolbar.plist"
launcher="$install_dir/start-toolbar.sh"
config_file="$install_dir/config.json"
uid="$(id -u "$target_user")"

mkdir -p "$install_dir" "$launch_agents_dir"
cp "$src_dir/share_toolbar.py" "$install_dir/share_toolbar.py"
if [[ ! -f "$config_file" ]]; then
  cp "$src_dir/config.template.json" "$config_file"
fi

sudo -u "$target_user" python3 -m pip install --user pystray pillow

cat >"$launcher" <<EOF
#!/usr/bin/env bash
exec python3 "$install_dir/share_toolbar.py" --config "$config_file"
EOF
chmod +x "$launcher"

cat >"$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.wtl.sharetoolbar</string>
  <key>ProgramArguments</key>
  <array>
    <string>$launcher</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <false/>
  <key>StandardOutPath</key>
  <string>$install_dir/stdout.log</string>
  <key>StandardErrorPath</key>
  <string>$install_dir/stderr.log</string>
</dict>
</plist>
EOF

chown -R "$target_user:staff" "$install_dir" "$launch_agents_dir"
launchctl bootout "gui/$uid" "$plist" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$uid" "$plist"
launchctl kickstart -k "gui/$uid/com.wtl.sharetoolbar"

echo "WTL Share Toolbar installed and set to autostart on macOS."
echo "Config file: $config_file"
