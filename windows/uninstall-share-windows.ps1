[CmdletBinding()]
param(
    [switch]$ConfirmExposure,
    [string]$ShareUser,
    [switch]$SkipUserRemoval
)

$ErrorActionPreference = "Stop"

function Read-OptionalValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt
    )
    $value = Read-Host $Prompt
    return $value.Trim()
}

function Test-IsAdministrator {
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentIdentity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-IsAdministrator)) {
    Write-Error "Run this script from an elevated PowerShell session."
}

Write-Host "This script removes the Windows share configuration created by this project." -ForegroundColor Yellow
if (-not $ConfirmExposure) {
    $ack = Read-Host "Type YES to continue"
    if ($ack -cne "YES") {
        Write-Error "Confirmation not accepted."
    }
}

$sharePath = "C:\Share-Windows"
$shareName = "Share-Windows"
$firewallGroup = "File and Printer Sharing"

Write-Host "Removing SMB share if present"
$existingShare = Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue
if ($null -ne $existingShare) {
    Remove-SmbShare -Name $shareName -Force
}

Write-Host "Restoring inbound SMB firewall rules to Any remote address"
Get-NetFirewallRule -DisplayGroup $firewallGroup -ErrorAction SilentlyContinue |
    Where-Object { $_.Direction -eq "Inbound" } |
    Set-NetFirewallAddressFilter -RemoteAddress "Any"

if (-not $SkipUserRemoval) {
    if ([string]::IsNullOrWhiteSpace($ShareUser)) {
        $ShareUser = Read-OptionalValue -Prompt "Enter the share user to remove (leave blank to keep user)"
    }

    if (-not [string]::IsNullOrWhiteSpace($ShareUser)) {
        Write-Host "Removing local user if present"
        $existingUser = Get-LocalUser -Name $ShareUser -ErrorAction SilentlyContinue
        if ($null -ne $existingUser) {
            Remove-LocalUser -Name $ShareUser
        }
    } else {
        Write-Host "No share user provided; skipping local user removal."
    }
} else {
    Write-Host "Skipping local user removal (--SkipUserRemoval)."
}

Write-Host "Share folder left in place at $sharePath"
Write-Host "Windows share uninstall complete."
