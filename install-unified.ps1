[CmdletBinding()]
param(
    [ValidateSet("auto", "windows")]
    [string]$Os = "auto",
    [switch]$NoPrompt
)

$ErrorActionPreference = "Stop"

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
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
    $confirm = Read-Host "Detected OS: $Os. Proceed with share + toolbar install? [Y/n]"
    if ($confirm -match "^[Nn]") {
        Write-Host "Cancelled."
        exit 0
    }
}

Write-Host "Running Windows share setup..."
& (Join-Path $repoRoot "windows\setup-share-windows.ps1") -ConfirmExposure

Write-Host "Running Windows toolbar setup..."
& (Join-Path $repoRoot "windows\install-toolbar-windows.ps1")

Write-Host "Unified install complete for Windows."
