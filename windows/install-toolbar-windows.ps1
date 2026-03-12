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

$repoRoot = Split-Path -Parent $PSScriptRoot
$toolbarSourceDir = Join-Path $repoRoot "toolbar"
$installDir = Join-Path $env:LOCALAPPDATA "WTL-Share-Net\toolbar"
$startupDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"
$shortcutPath = Join-Path $startupDir "WTL Share Toolbar.lnk"
$configPath = Join-Path $installDir "config.json"
$launcherPath = Join-Path $installDir "start-toolbar.cmd"
$pythonExe = $null
$pipInstallCmd = $null

function Resolve-PythonRuntime {
    $resolved = @{
        PythonExe = $null
        PipCmd = $null
    }

    if (Get-Command py -ErrorAction SilentlyContinue) {
        try {
            $candidate = (& py -3 -c "import sys; print(sys.executable)" 2>$null).Trim()
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
                $resolved.PythonExe = $candidate
                $resolved.PipCmd = "py -3 -m pip install --user pystray pillow"
                return $resolved
            }
        } catch {}
    }

    if (Get-Command python -ErrorAction SilentlyContinue) {
        try {
            $candidate = (& python -c "import sys; print(sys.executable)" 2>$null).Trim()
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path $candidate)) {
                $resolved.PythonExe = $candidate
                $resolved.PipCmd = "python -m pip install --user pystray pillow"
                return $resolved
            }
        } catch {}
    }

    $possiblePaths = @(
        "$env:LocalAppData\Programs\Python\Python312\python.exe",
        "$env:LocalAppData\Programs\Python\Python311\python.exe",
        "C:\Program Files\Python312\python.exe",
        "C:\Program Files\Python311\python.exe"
    )

    foreach ($path in $possiblePaths) {
        if (Test-Path $path) {
            $resolved.PythonExe = $path
            $resolved.PipCmd = "`"$path`" -m pip install --user pystray pillow"
            return $resolved
        }
    }

    return $resolved
}

function Install-Python3 {
    Write-Host "Python 3 not found. Attempting automatic install..."

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        try {
            winget install -e --id Python.Python.3.12 --scope machine --accept-source-agreements --accept-package-agreements --silent --disable-interactivity
            return
        } catch {
            Write-Warning "winget install failed: $($_.Exception.Message)"
        }
    }

    if (Get-Command choco -ErrorAction SilentlyContinue) {
        try {
            choco install python --yes --no-progress
            return
        } catch {
            Write-Warning "choco install failed: $($_.Exception.Message)"
        }
    }
}

# Resolve a real Python interpreter. `py`/`python` aliases may exist without Python actually installed.
$runtime = Resolve-PythonRuntime
$pythonExe = $runtime.PythonExe
$pipInstallCmd = $runtime.PipCmd

if (-not $pythonExe) {
    Install-Python3
    Start-Sleep -Seconds 2
    $runtime = Resolve-PythonRuntime
    $pythonExe = $runtime.PythonExe
    $pipInstallCmd = $runtime.PipCmd
}

if (-not $pythonExe) {
    Write-Error "Python 3 is required but could not be auto-installed. Install Python 3 and rerun this script."
}

New-Item -ItemType Directory -Path $installDir -Force | Out-Null
Copy-Item -Path (Join-Path $toolbarSourceDir "share_toolbar.py") -Destination (Join-Path $installDir "share_toolbar.py") -Force

if (-not (Test-Path $configPath)) {
    Copy-Item -Path (Join-Path $toolbarSourceDir "config.template.json") -Destination $configPath -Force
}

Write-Host "Installing Python dependencies for toolbar"
Invoke-Expression $pipInstallCmd

$pythonw = Join-Path (Split-Path $pythonExe) "pythonw.exe"
if (-not (Test-Path $pythonw)) {
    $pythonw = $pythonExe
}

$launcherContent = @"
@echo off
"$pythonw" "$installDir\share_toolbar.py" --config "$configPath"
"@
Set-Content -Path $launcherPath -Value $launcherContent -Encoding ascii -Force

$wsh = New-Object -ComObject WScript.Shell
$shortcut = $wsh.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $launcherPath
$shortcut.WorkingDirectory = $installDir
$shortcut.WindowStyle = 7
$shortcut.Save()

Start-Process -FilePath $launcherPath -WindowStyle Hidden

Write-Host "WTL Share Toolbar installed and set to autostart."
Write-Host "Config file: $configPath"
