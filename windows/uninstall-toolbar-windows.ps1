[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    Write-Error "Run this script from an elevated PowerShell session."
}

$installDir = Join-Path $env:LOCALAPPDATA "WTL-Share-Net\toolbar"
$startupDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
$shortcutPath = Join-Path $startupDir "WTL Share Toolbar.lnk"

Get-Process -Name pythonw,python -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -like "*WTL-Share-Net*" } |
    Stop-Process -Force -ErrorAction SilentlyContinue

if (Test-Path $shortcutPath) {
    Remove-Item $shortcutPath -Force
}

if (Test-Path $installDir) {
    Remove-Item $installDir -Recurse -Force
}

Write-Host "WTL Share Toolbar uninstalled from Windows."
