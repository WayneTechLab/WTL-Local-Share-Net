[CmdletBinding()]
param()

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

$requiredSetupPassphrase = "WTL-SETUP-2026"
$enteredPassphrase = Read-Host "Enter setup passphrase"
if ($enteredPassphrase -ne $requiredSetupPassphrase) {
    Write-Error "Invalid setup passphrase."
}

$ubuntuIp = Read-RequiredValue -Prompt "Enter Ubuntu machine IP"
$shareUser = Read-RequiredValue -Prompt "Enter the local username Ubuntu will use"
$sharePassword = Read-Host "Enter the password for this share user" -AsSecureString
$sharePasswordConfirm = Read-Host "Confirm the password" -AsSecureString

$bstrOne = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sharePassword)
$bstrTwo = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($sharePasswordConfirm)
try {
    $plainOne = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstrOne)
    $plainTwo = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstrTwo)
} finally {
    if ($bstrOne -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstrOne) }
    if ($bstrTwo -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstrTwo) }
}

if ($plainOne -ne $plainTwo) {
    Write-Error "Passwords do not match."
}

$sharePath = "C:\Share-Windows"
$shareName = "Share-Windows"
$sharePrincipal = "$env:COMPUTERNAME\$shareUser"
$firewallGroup = "File and Printer Sharing"

Write-Host "Creating folder $sharePath"
New-Item -ItemType Directory -Force -Path $sharePath | Out-Null

Write-Host "Creating or updating local user $shareUser"
$existingUser = Get-LocalUser -Name $shareUser -ErrorAction SilentlyContinue
if ($null -eq $existingUser) {
    New-LocalUser `
        -Name $shareUser `
        -Password $sharePassword `
        -FullName "Ubuntu Share User" `
        -Description "Restricted SMB account for Ubuntu access" `
        -PasswordNeverExpires:$true `
        -AccountNeverExpires | Out-Null
} else {
    Set-LocalUser -Name $shareUser -Password $sharePassword
}

Write-Host "Locking NTFS permissions"
icacls $sharePath /inheritance:r | Out-Null
icacls $sharePath /grant:r "Administrators:(OI)(CI)(F)" | Out-Null
icacls $sharePath /grant:r "$sharePrincipal:(OI)(CI)(M)" | Out-Null
icacls $sharePath /remove "Users" "Authenticated Users" "Everyone" 2>$null | Out-Null

Write-Host "Recreating SMB share"
$existingShare = Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue
if ($null -ne $existingShare) {
    Remove-SmbShare -Name $shareName -Force
}

New-SmbShare `
    -Name $shareName `
    -Path $sharePath `
    -FullAccess "Administrators" `
    -ChangeAccess $sharePrincipal `
    -Description "Locked share for the Ubuntu machine" | Out-Null

Write-Host "Hardening SMB server settings"
Set-SmbServerConfiguration -EnableSMB1Protocol $false -Force | Out-Null
Set-SmbServerConfiguration -RequireSecuritySignature $true -Force | Out-Null
Set-SmbServerConfiguration -EncryptData $true -Force | Out-Null

Write-Host "Restricting inbound SMB firewall rules to $ubuntuIp"
Get-NetFirewallRule -DisplayGroup $firewallGroup -ErrorAction SilentlyContinue |
    Where-Object { $_.Direction -eq "Inbound" } |
    Set-NetFirewallRule -Enabled True -Profile Private

Get-NetFirewallRule -DisplayGroup $firewallGroup -ErrorAction SilentlyContinue |
    Where-Object { $_.Direction -eq "Inbound" } |
    Set-NetFirewallAddressFilter -RemoteAddress $ubuntuIp

Write-Host ""
Write-Host "Share-Windows setup complete."
Write-Host "Folder: $sharePath"
Write-Host "UNC path: \\$env:COMPUTERNAME\$shareName"
Write-Host "Allowed remote IP: $ubuntuIp"
Write-Host "Share username: $sharePrincipal"
