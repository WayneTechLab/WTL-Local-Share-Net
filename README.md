# WTL Local Share Net

Open source utility for creating a locked-down local SMB share on Windows, Ubuntu, and macOS.

## About

WTL Local Share Net is maintained by Wayne Tech Lab LLC.  
Website: [www.WayneTechLab.com](https://www.WayneTechLab.com)

## Disclaimer

Use this software at your own risk. Wayne Tech Lab LLC provides this project "as is", without warranties or guarantees of any kind, express or implied, including but not limited to merchantability, fitness for a particular purpose, security, availability, or non-infringement. You are responsible for validating configuration, access controls, and legal/security compliance in your own environment.

This repo creates:

- `C:\Share-Windows` shared as `Share-Windows`
- `/Share-Ubuntu` shared as `Share-Ubuntu`
- `/Users/Shared/Share-macOS` shared as `Share-macOS`

Each share is restricted to a client scope (auto-detected local subnet by default, or explicit IP/CIDR override) and requires a dedicated username and password.

## Layout

- `windows/setup-share-windows.ps1`
- `windows/uninstall-share-windows.ps1`
- `windows/install-toolbar-windows.ps1`
- `windows/uninstall-toolbar-windows.ps1`
- `ubuntu/setup-share-ubuntu.sh`
- `ubuntu/fix-share-ubuntu.sh`
- `ubuntu/uninstall-share-ubuntu.sh`
- `ubuntu/install-toolbar-ubuntu.sh`
- `ubuntu/uninstall-toolbar-ubuntu.sh`
- `macos/setup-share-macos.sh`
- `macos/uninstall-share-macos.sh`
- `macos/install-toolbar-macos.sh`
- `macos/uninstall-toolbar-macos.sh`
- `toolbar/share_toolbar.py`
- `install-toolbar.sh`
- `uninstall-toolbar.sh`
- `install-unified.sh`
- `install-unified.ps1`

## Confirmation Model

- Explicit confirmation gate before changes are made
- Automatic client scope detection from local network configuration
- Automatic system preflight before share apply (VPN/LAN + firewall/service checks)
- Interactive share username and password prompts
- SMB guest access disabled
- SMB1 disabled on Windows
- SMB3 required on Ubuntu
- Firewall restricted to auto-detected client subnet (or explicit IP/CIDR) on port `445`

Installers require explicit exposure confirmation before they make changes.

- Interactive mode: type `YES` when prompted.
- Non-interactive mode: pass the confirmation flag (`-ConfirmExposure` on Windows, `--confirm-exposure` on Linux/macOS).

## Windows

Unified installer (recommended):

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\install-unified.ps1
```

Run PowerShell as Administrator:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\windows\setup-share-windows.ps1
```

Optional non-interactive confirmation:

```powershell
.\windows\setup-share-windows.ps1 -ConfirmExposure
```

Fastest one-liner (recommended):

```powershell
& ([scriptblock]::Create((irm "https://raw.githubusercontent.com/WayneTechLab/WTL-Local-Share-Net/main/windows/setup-share-windows.ps1"))) -ConfirmExposure
```

Override auto-detected scope with explicit IP/CIDR:

```powershell
.\windows\setup-share-windows.ps1 -ConfirmExposure -ClientScope <CLIENT_IP_OR_CIDR>
```

Windows preflight now automatically:

- Sets active network profile to `Private` on the primary interface
- Enables `File and Printer Sharing` firewall group
- Applies `nordvpn set lan-discovery on` and `nordvpn set killswitch off` when NordVPN CLI is installed

To remove the Windows share:

```powershell
.\windows\uninstall-share-windows.ps1
```

Windows prompts for:

- allowed client scope (auto-detect default)
- SMB username
- SMB password + confirmation

## Ubuntu

Unified installer (recommended):

```bash
bash ./install-unified.sh
```

Run from a shell with sudo:

```bash
sudo bash ./ubuntu/setup-share-ubuntu.sh
```

Optional non-interactive confirmation:

```bash
sudo bash ./ubuntu/setup-share-ubuntu.sh --confirm-exposure
```

Recommended non-interactive run:

```bash
sudo bash ./ubuntu/setup-share-ubuntu.sh --confirm-exposure --windows-ip <WINDOWS_IP> --share-user <SMB_USER>
```

Auto mode (no fixed Windows IP required):

```bash
sudo bash ./ubuntu/setup-share-ubuntu.sh --confirm-exposure --share-user <SMB_USER>
```

Ubuntu preflight now automatically:

- Applies `nordvpn set lan-discovery on` and `nordvpn set killswitch off` when NordVPN CLI is installed
- Then validates routing and continues with Samba/UFW setup

If Samba config was damaged by bad pasted commands, run the repair script:

```bash
sudo bash ./ubuntu/fix-share-ubuntu.sh --windows-ip <WINDOWS_IP> --share-user <SMB_USER>
```

Auto-detect scope during repair:

```bash
sudo bash ./ubuntu/fix-share-ubuntu.sh --share-user <SMB_USER>
```

To remove the Ubuntu share:

```bash
sudo bash ./ubuntu/uninstall-share-ubuntu.sh
```

Ubuntu prompts for:

- allowed client scope (auto-detect default)
- SMB username
- SMB/network-share password + confirmation
- does not overwrite Linux login password

Mount the Windows share from Ubuntu:

```bash
sudo bash ./ubuntu/mount-share-windows.sh
```

Non-interactive example:

```bash
sudo bash ./ubuntu/mount-share-windows.sh --windows-ip <WINDOWS_IP> --share-name Share-Windows --username <WINDOWS_USER> --domain <WINDOWS_MACHINE_OR_DOMAIN> --password <PASSWORD>
```

## GitHub Raw Execution

Windows:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
irm https://raw.githubusercontent.com/WayneTechLab/WTL-Local-Share-Net/main/windows/setup-share-windows.ps1 | iex
```

With explicit confirmation flag:

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/WayneTechLab/WTL-Local-Share-Net/main/windows/setup-share-windows.ps1))) -ConfirmExposure
```

Ubuntu:

```bash
curl -fsSL https://raw.githubusercontent.com/WayneTechLab/WTL-Local-Share-Net/main/ubuntu/setup-share-ubuntu.sh | sudo bash
```

With explicit confirmation flag:

```bash
curl -fsSL https://raw.githubusercontent.com/WayneTechLab/WTL-Local-Share-Net/main/ubuntu/setup-share-ubuntu.sh | sudo bash -s -- --confirm-exposure
```

macOS:

```bash
curl -fsSL https://raw.githubusercontent.com/WayneTechLab/WTL-Local-Share-Net/main/macos/setup-share-macos.sh | sudo bash -s -- --confirm-exposure
```

## macOS

Unified installer (recommended):

```bash
bash ./install-unified.sh
```

Run on macOS with sudo:

```bash
sudo bash ./macos/setup-share-macos.sh --confirm-exposure
```

Recommended non-interactive run:

```bash
sudo bash ./macos/setup-share-macos.sh --confirm-exposure --client-ip <CLIENT_IP_OR_CIDR> --share-user <SMB_USER>
```

Auto mode (no fixed client IP required):

```bash
sudo bash ./macos/setup-share-macos.sh --confirm-exposure --share-user <SMB_USER>
```

macOS preflight now automatically:

- Adds/unblocks `/usr/sbin/smbd` in macOS Application Firewall (when available)
- Applies `nordvpn set lan-discovery on` and `nordvpn set killswitch off` when NordVPN CLI is installed

To remove the macOS share configuration:

```bash
sudo bash ./macos/uninstall-share-macos.sh --confirm-exposure
```

macOS prompts for:

- allowed client scope (auto-detect default)
- SMB username
- SMB/network-share password + confirmation (this is the selected macOS account password, validated with `dscl`)

## Verify

Ubuntu checks:

```bash
sudo systemctl is-active smbd
sudo ufw status numbered | grep '445/tcp'
sudo testparm -s | grep -A8 '^\[Share-Ubuntu\]'
```

Windows checks:

```powershell
Test-NetConnection <SHARE_HOST_IP> -Port 445
net use Z: \\<SHARE_HOST_IP>\Share-Ubuntu /user:<SMB_USER> *
explorer Z:
```

## Troubleshooting

- `Access is denied` from `Set-NetFirewallRule` on Windows: run PowerShell as Administrator.
- Windows cannot reach Ubuntu and ping fails while VPN is active: on Ubuntu, run `nordvpn set lan-discovery on`.
- `Share-Ubuntu` missing in `smbclient -L`: run `sudo testparm -s` and then `sudo bash ./ubuntu/fix-share-ubuntu.sh --windows-ip <WINDOWS_IP> --share-user <USER>`.
- `NT_STATUS_LOGON_FAILURE`: reset Samba password with `sudo smbpasswd -a <USER>` and `sudo smbpasswd -e <USER>`.
- macOS SMB login uses the existing macOS account password for the `--share-user` account.
- Toolbar icon not visible on Windows: run `.\windows\install-toolbar-windows.ps1` in Administrator PowerShell, then check `%LOCALAPPDATA%\WTL-Share-Net\toolbar\toolbar.log` (for the interactive user profile).
- Toolbar icon not visible on Ubuntu: run `sudo bash ./ubuntu/install-toolbar-ubuntu.sh` from the desktop user session, then check `~/.local/share/wtl-share-net/toolbar/toolbar.log`.

## Toolbar App

The toolbar app runs in the system tray/menubar, autostarts with the OS, and provides a dropdown to:

- See configured device online/offline status (SMB port 445 probe)
- Open configured SMB shares directly
- Rescan now
- Run auto-discovery
- Open toolbar config

Install from terminal/shell (auto-detect Linux/macOS):

```bash
sudo bash ./install-toolbar.sh
```

Uninstall from terminal/shell (auto-detect Linux/macOS):

```bash
sudo bash ./uninstall-toolbar.sh
```

Windows install (PowerShell, Administrator):

```powershell
.\windows\install-toolbar-windows.ps1
```

Notes:

- Windows installer auto-attempts Python 3 install (`winget` first, `choco` fallback) if Python is missing.

Windows uninstall:

```powershell
.\windows\uninstall-toolbar-windows.ps1
```

All toolbar installers/uninstallers require elevated privileges:

- Windows: run PowerShell as Administrator
- Ubuntu/macOS: run with `sudo`

Config file locations:

- Windows: `%LOCALAPPDATA%\WTL-Share-Net\toolbar\config.json`
- Ubuntu: `~/.local/share/wtl-share-net/toolbar/config.json`
- macOS: `~/Library/Application Support/WTL-Share-Net/toolbar/config.json`

Auto-discovery behavior:

- On first run, toolbar scans local `/24` subnets inferred from local IPv4 addresses for hosts with SMB port `445` open.
- Newly discovered hosts are added to config as `Discovered <ip>`.
- You can rerun discovery any time from the toolbar dropdown (`Run auto-discovery`).
- Discovery settings are in config under `auto_discovery` (`enabled`, `timeout_seconds`, `max_workers`, `targets`).

## Suggested First Push

```powershell
git init
git checkout -b codex/wtl-local-share-net
git add .
git commit -m "Add local share setup scripts for Windows and Ubuntu"
git remote add origin https://github.com/YOUR_GITHUB_USER/YOUR_REPO.git
git push -u origin codex/wtl-local-share-net
```

## License

This project is open source under the MIT License. Copyright (c) Wayne Tech Lab LLC.
