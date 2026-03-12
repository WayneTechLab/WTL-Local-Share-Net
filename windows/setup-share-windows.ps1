[CmdletBinding()]
param(
    [switch]$ConfirmExposure,
    [string]$ClientScope
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

function Get-AutoClientScope {
    $defaultRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
        Sort-Object RouteMetric, ifMetric |
        Select-Object -First 1

    if ($null -eq $defaultRoute) {
        Write-Error "Unable to detect primary network route."
    }

    $ip = Get-NetIPAddress -AddressFamily IPv4 -InterfaceIndex $defaultRoute.InterfaceIndex -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -notlike "169.254.*" } |
        Select-Object -First 1

    if ($null -eq $ip) {
        Write-Error "Unable to detect primary IPv4 address."
    }

    $ipBytes = [System.Net.IPAddress]::Parse($ip.IPAddress).GetAddressBytes()
    [Array]::Reverse($ipBytes)
    $ipInt = [BitConverter]::ToUInt32($ipBytes, 0)

    $prefix = [int]$ip.PrefixLength
    if ($prefix -eq 0) {
        $maskInt = [uint32]0
    } else {
        $maskInt = [uint32]::MaxValue -shl (32 - $prefix)
    }

    $networkInt = $ipInt -band $maskInt
    $networkBytes = [BitConverter]::GetBytes($networkInt)
    [Array]::Reverse($networkBytes)
    $network = [System.Net.IPAddress]::new($networkBytes).ToString()

    return "$network/$prefix"
}

function Apply-SystemPreflight {
    param(
        [Parameter(Mandatory = $true)]
        [int]$InterfaceIndex
    )

    Write-Host "Applying Windows system preflight"

    try {
        $profile = Get-NetConnectionProfile -InterfaceIndex $InterfaceIndex -ErrorAction Stop
        if ($null -ne $profile -and $profile.NetworkCategory -ne "Private") {
            Write-Host "Setting active network profile to Private"
            Set-NetConnectionProfile -InterfaceIndex $InterfaceIndex -NetworkCategory Private -ErrorAction Stop
        }
    } catch {
        Write-Warning "Could not set network profile to Private automatically: $($_.Exception.Message)"
    }

    try {
        Write-Host "Enabling File and Printer Sharing firewall rule group"
        Set-NetFirewallRule -DisplayGroup "File and Printer Sharing" -Enabled True -ErrorAction Stop | Out-Null
    } catch {
        Write-Warning "Could not enable firewall rule group automatically: $($_.Exception.Message)"
    }

    $nordvpn = Get-Command nordvpn -ErrorAction SilentlyContinue
    if ($null -ne $nordvpn) {
        Write-Host "Applying NordVPN LAN settings (if supported)"
        try { nordvpn set lan-discovery on | Out-Null } catch { Write-Warning "NordVPN LAN discovery update failed." }
        try { nordvpn set killswitch off | Out-Null } catch { Write-Warning "NordVPN kill switch update failed." }
    }
}

if (-not (Test-IsAdministrator)) {
    Write-Error "Run this script from an elevated PowerShell session."
}

Write-Host "This script opens an SMB network share on this computer." -ForegroundColor Yellow
Write-Host "You are about to expose a network share and firewall scope on this machine." -ForegroundColor Yellow
if (-not $ConfirmExposure) {
    $ack = Read-Host "Type YES to continue"
    if ($ack -cne "YES") {
        Write-Error "Confirmation not accepted."
    }
}

$autoClientScope = Get-AutoClientScope
$defaultRoute = Get-NetRoute -DestinationPrefix "0.0.0.0/0" -ErrorAction SilentlyContinue |
    Sort-Object RouteMetric, ifMetric |
    Select-Object -First 1
if ($null -eq $defaultRoute) {
    Write-Error "Unable to detect primary route for preflight."
}

Apply-SystemPreflight -InterfaceIndex $defaultRoute.InterfaceIndex

if ([string]::IsNullOrWhiteSpace($ClientScope)) {
    $enteredScope = Read-Host "Enter allowed client IP/CIDR (press Enter for auto: $autoClientScope)"
    if ([string]::IsNullOrWhiteSpace($enteredScope)) {
        $ClientScope = $autoClientScope
    } else {
        $ClientScope = $enteredScope.Trim()
    }
}

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
icacls $sharePath /grant:r "${sharePrincipal}:(OI)(CI)(M)" | Out-Null
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

Write-Host "Restricting inbound SMB firewall rules to $ClientScope"
$inboundRules = Get-NetFirewallRule -DisplayGroup $firewallGroup -ErrorAction SilentlyContinue |
    Where-Object { $_.Direction -eq "Inbound" }

$inboundRules | Set-NetFirewallRule -Enabled True -Profile Private

$inboundRules |
    Get-NetFirewallAddressFilter |
    Set-NetFirewallAddressFilter -RemoteAddress $ClientScope

Write-Host ""
Write-Host "Share-Windows setup complete."
Write-Host "Folder: $sharePath"
Write-Host "UNC path: \\$env:COMPUTERNAME\$shareName"
Write-Host "Allowed client scope: $ClientScope"
Write-Host "Share username: $sharePrincipal"
