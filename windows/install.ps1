# Copyright 2026 Matt Harrison
# SPDX-License-Identifier: Apache-2.0

# install.ps1 — Spore OS Windows installer (User-level)
# Must be run from the dist\ directory (or alongside dist\ contents).
# Safe to re-run as an upgrade — all steps are idempotent.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Step    ([string]$msg) { Write-Host ""; Write-Host ">> $msg" -ForegroundColor Cyan }
function Success ([string]$msg) { Write-Host "OK $msg" -ForegroundColor Green }
function Warn    ([string]$msg) { Write-Host "!! $msg" -ForegroundColor Yellow }
function Die     ([string]$msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

$ScriptDir = $PSScriptRoot
$DistDir   = $ScriptDir   # install.ps1 lives inside dist\ after build

# ---------------------------------------------------------------------------
# Detect system architecture
# ---------------------------------------------------------------------------
$Arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }

# ---------------------------------------------------------------------------
# Paths (User-level)
# ---------------------------------------------------------------------------
$InstallDir   = Join-Path $env:LOCALAPPDATA 'spore-os'
$BinDir       = Join-Path $InstallDir 'bin'
$DataDir      = $InstallDir
$LogDir       = Join-Path $DataDir 'logs'
$HubDir       = Join-Path $DataDir 'hub'
$ManifestDir  = Join-Path $DataDir 'manifests'
$RunDir       = Join-Path $DataDir 'run'
$StartMenuDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Spore OS'

$env:SPORE_DATA_DIR = $InstallDir

$Nodes = @('spore-shell', 'spore-witness', 'spore-log', 'spore-dialog', 'spore')

# ---------------------------------------------------------------------------
# 1. Create required directories
# ---------------------------------------------------------------------------
Step "Creating user-level directories"

$Dirs = @(
    $InstallDir,
    $BinDir,
    $DataDir,
    (Join-Path $DataDir 'data'),
    $HubDir,
    $ManifestDir,
    $RunDir,
    $LogDir
)

foreach ($dir in $Dirs) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    Success $dir
}

# ---------------------------------------------------------------------------
# 2. Stop existing daemon and node processes
# ---------------------------------------------------------------------------
Step "Stopping existing spored daemon and node processes"

$userSpored = Get-Process -Name 'spored' -ErrorAction SilentlyContinue
if ($userSpored) {
    Stop-Process -Name 'spored' -Force -ErrorAction SilentlyContinue
    Success "Stopped running spored.exe"
}

foreach ($node in $Nodes) {
    if (Get-Process -Name $node -ErrorAction SilentlyContinue) {
        Stop-Process -Name $node -Force -ErrorAction SilentlyContinue
        Success "Stopped running ${node}.exe"
    }
}

# ---------------------------------------------------------------------------
# 3. Install binaries
# ---------------------------------------------------------------------------
Step "Installing binaries to $InstallDir"

Copy-Item "$DistDir\$Arch\spored.exe" "$InstallDir\spored.exe" -Force
Success "Installed spored.exe"

foreach ($node in $Nodes) {
    Copy-Item "$DistDir\$Arch\bin\${node}.exe" "$BinDir\${node}.exe" -Force
    Success "Installed ${node}.exe"
}

# ---------------------------------------------------------------------------
# 4. Install hub manifest
# ---------------------------------------------------------------------------
Step "Installing hub manifest"

Copy-Item "$DistDir\spored.manifest.spore.yaml" "$HubDir\spored.manifest.spore.yaml" -Force
Success "Hub manifest installed at $HubDir"

# ---------------------------------------------------------------------------
# 5. Add install directories to the user PATH
# ---------------------------------------------------------------------------
Step "Updating user PATH"

$userPath = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
$changed  = $false

foreach ($p in @($InstallDir, $BinDir)) {
    if ($userPath -notlike "*$p*") {
        if ($userPath -and -not $userPath.EndsWith(';')) { $userPath += ";" }
        $userPath += $p
        $changed = $true
        Success "Added to user PATH: $p"
    } else {
        Warn "Already in user PATH: $p - skipping"
    }
}

if ($changed) {
    [System.Environment]::SetEnvironmentVariable('PATH', $userPath, 'User')
    $env:PATH = $env:PATH + ";" + $InstallDir + ";" + $BinDir
}

# Persist SPORE_DATA_DIR environment variable
[System.Environment]::SetEnvironmentVariable('SPORE_DATA_DIR', $InstallDir, 'User')

# ---------------------------------------------------------------------------
# 6. Start spored.exe background process
# ---------------------------------------------------------------------------
Step "Starting Spore OS daemon (spored.exe) in background"

Start-Process -FilePath "$InstallDir\spored.exe" -WorkingDirectory $InstallDir -WindowStyle Hidden
Start-Sleep -Seconds 2
Success "Daemon started"

# ---------------------------------------------------------------------------
# 7. Install node manifests
# ---------------------------------------------------------------------------
Step "Installing node manifests"

$manifests = @(Get-ChildItem "$DistDir\nodes\*.manifest.spore.yaml" -ErrorAction SilentlyContinue)

if ($manifests.Count -eq 0) {
    Warn "No node manifests found in $DistDir\nodes\ - skipping"
} else {
    foreach ($manifest in $manifests) {
        & "$InstallDir\spored.exe" install $manifest.FullName
        if ($LASTEXITCODE -ne 0) { Die "Failed to install manifest: $($manifest.Name)" }
        Success "Installed manifest: $($manifest.Name)"
    }

    Step "Restarting daemon to apply manifests"
    Stop-Process -Name 'spored' -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Start-Process -FilePath "$InstallDir\spored.exe" -WorkingDirectory $InstallDir -WindowStyle Hidden
    Success "Daemon restarted"
}

# ---------------------------------------------------------------------------
# 8. Create Start Menu shortcuts
# ---------------------------------------------------------------------------
Step "Creating Start Menu shortcuts"

New-Item -ItemType Directory -Force -Path $StartMenuDir | Out-Null

function New-StartMenuShortcut ([string]$ShortcutName, [string]$TargetBin) {
    $WShell   = New-Object -ComObject WScript.Shell
    $Shortcut = $WShell.CreateShortcut("$StartMenuDir\$ShortcutName.lnk")
    $Shortcut.TargetPath       = $TargetBin
    $Shortcut.WorkingDirectory = Split-Path $TargetBin
    $Shortcut.WindowStyle      = 1   # Normal window
    $Shortcut.Save()
    Success "Created: $StartMenuDir\$ShortcutName.lnk"
}

New-StartMenuShortcut -ShortcutName 'Spore Shell'   -TargetBin "$BinDir\spore-shell.exe"
New-StartMenuShortcut -ShortcutName 'Spore Witness' -TargetBin "$BinDir\spore-witness.exe"

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host "  Spore OS installation complete!" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host ""
