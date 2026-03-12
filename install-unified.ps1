[CmdletBinding()]
param(
    [ValidateSet("auto", "windows")]
    [string]$Os = "auto",
    [ValidateSet("clean-reinstall", "install-only", "update-app-only", "share-only", "toolbar-only", "uninstall-only")]
    [string]$Mode = "clean-reinstall",
    [switch]$NoPrompt
)

$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-LegacyCleanup {
    Write-Host "Running legacy cleanup pass..."

    Get-Process -Name pythonw,python -ErrorAction SilentlyContinue |
        Where-Object {
            ($_.Path -like "*WTL-Share-Net*") -or
            ($_.Path -like "*share_toolbar*")
        } |
        Stop-Process -Force -ErrorAction SilentlyContinue

    $userRoots = Get-ChildItem "$env:SystemDrive\Users" -Directory -ErrorAction SilentlyContinue
    foreach ($root in $userRoots) {
        $startup = Join-Path $root.FullName "AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
        $toolbarLocal = Join-Path $root.FullName "AppData\Local\WTL-Share-Net\toolbar"
        $legacyToolbarLocal = Join-Path $root.FullName "AppData\Local\WTLShareNet\toolbar"

        foreach ($shortcutName in @("WTL Share Toolbar.lnk", "WTL-Share-Toolbar.lnk")) {
            $shortcutPath = Join-Path $startup $shortcutName
            if (Test-Path $shortcutPath) {
                Remove-Item $shortcutPath -Force -ErrorAction SilentlyContinue
            }
        }

        foreach ($dirPath in @($toolbarLocal, $legacyToolbarLocal)) {
            if (Test-Path $dirPath) {
                Remove-Item $dirPath -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }
}

if (-not (Test-IsAdministrator)) {
    Write-Error "Run this script from an elevated PowerShell session."
}

$repoRoot = $PSScriptRoot
$detectedOs = "windows"

if ($Os -eq "auto") {
    $Os = $detectedOs
}

if ($Os -ne $detectedOs) {
    Write-Error "Selected OS '$Os' does not match this host ('$detectedOs'). Run on target machine."
}

if (-not $NoPrompt) {
    $confirm = Read-Host "Detected OS: $Os. Proceed with mode '$Mode'? [Y/n]"
    if ($confirm -match "^[Nn]") {
        Write-Host "Cancelled."
        exit 0
    }
}

if ($Mode -in @("clean-reinstall", "update-app-only", "uninstall-only")) {
    Invoke-LegacyCleanup
}

if ($Mode -in @("clean-reinstall", "uninstall-only")) {
    Write-Host "Running Windows share uninstall..."
    try {
        & (Join-Path $repoRoot "windows\uninstall-share-windows.ps1") -ConfirmExposure -SkipUserRemoval
    } catch {
        Write-Warning "Share uninstall step failed: $($_.Exception.Message)"
    }
}

if ($Mode -in @("clean-reinstall", "update-app-only", "uninstall-only")) {
    Write-Host "Running Windows toolbar uninstall..."
    try {
        & (Join-Path $repoRoot "windows\uninstall-toolbar-windows.ps1")
    } catch {
        Write-Warning "Toolbar uninstall step failed: $($_.Exception.Message)"
    }
}

if ($Mode -eq "uninstall-only") {
    Write-Host "Unified uninstall complete for Windows."
    exit 0
}

if ($Mode -in @("clean-reinstall", "install-only", "share-only")) {
    Write-Host "Running Windows share setup..."
    & (Join-Path $repoRoot "windows\setup-share-windows.ps1") -ConfirmExposure
}

if ($Mode -in @("clean-reinstall", "install-only", "update-app-only", "toolbar-only")) {
    Write-Host "Running Windows toolbar setup..."
    & (Join-Path $repoRoot "windows\install-toolbar-windows.ps1")
}

Write-Host "Unified '$Mode' complete for Windows."
