# WTL Local Share Net

Paired scripts for creating a locked-down local SMB share on Windows and Ubuntu.

This repo creates:

- `C:\Share-Windows` shared as `Share-Windows`
- `/Share-Ubuntu` shared as `Share-Ubuntu`

Each share is restricted to a single remote host IP and requires a dedicated username and password.

## Layout

- `windows/setup-share-windows.ps1`
- `windows/uninstall-share-windows.ps1`
- `ubuntu/setup-share-ubuntu.sh`
- `ubuntu/uninstall-share-ubuntu.sh`

## Security Model

- Interactive setup passphrase gate before changes are made
- Interactive share username and password prompts
- SMB guest access disabled
- SMB1 disabled on Windows
- SMB3 required on Ubuntu
- Firewall restricted to the other machine's IP on port `445`

The setup passphrase is only a light gate. If the repo is public, anyone can inspect the script logic. Use a private repo if that matters.

## Windows

Run PowerShell as Administrator:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
.\windows\setup-share-windows.ps1
```

To remove the Windows share:

```powershell
.\windows\uninstall-share-windows.ps1
```

## Ubuntu

Run from a shell with sudo:

```bash
sudo bash ./ubuntu/setup-share-ubuntu.sh
```

To remove the Ubuntu share:

```bash
sudo bash ./ubuntu/uninstall-share-ubuntu.sh
```

## GitHub Raw Execution

Replace `YOUR_GITHUB_USER` and `YOUR_REPO`.

Windows:

```powershell
Set-ExecutionPolicy Bypass -Scope Process -Force
irm https://raw.githubusercontent.com/YOUR_GITHUB_USER/YOUR_REPO/main/windows/setup-share-windows.ps1 | iex
```

Ubuntu:

```bash
curl -fsSL https://raw.githubusercontent.com/YOUR_GITHUB_USER/YOUR_REPO/main/ubuntu/setup-share-ubuntu.sh | sudo bash
```

## Suggested First Push

```powershell
git init
git checkout -b codex/wtl-local-share-net
git add .
git commit -m "Add local share setup scripts for Windows and Ubuntu"
git remote add origin https://github.com/YOUR_GITHUB_USER/YOUR_REPO.git
git push -u origin codex/wtl-local-share-net
```
