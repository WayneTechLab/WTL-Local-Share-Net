[CmdletBinding()]
param(
    [switch]$ConfirmExposure
)

$ErrorActionPreference = "Stop"

function Read-RequiredValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt
    )

    do {
        $value = Read-Host $Prompt
    } while ([string]::IsNullOrWhiteSpace($value))

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

$shareUser = Read-RequiredValue -Prompt "Enter the share user to remove"
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

Write-Host "Removing local user if present"
$existingUser = Get-LocalUser -Name $shareUser -ErrorAction SilentlyContinue
if ($null -ne $existingUser) {
    Remove-LocalUser -Name $shareUser
}

Write-Host "Share folder left in place at $sharePath"
Write-Host "Windows share uninstall complete."
