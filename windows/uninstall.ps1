# Copyright 2026 Matt Harrison
# SPDX-License-Identifier: Apache-2.0

# uninstall.ps1 — Spore OS Windows uninstaller (User-level)
# Safe to run — tolerate already-absent targets.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Step    ([string]$msg) { Write-Host ""; Write-Host ">> $msg" -ForegroundColor Cyan }
function Success ([string]$msg) { Write-Host "OK $msg" -ForegroundColor Green }
function Warn    ([string]$msg) { Write-Host "!! $msg" -ForegroundColor Yellow }
function Die     ([string]$msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# ---------------------------------------------------------------------------
# Confirmation
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  +----------------------------------------------------------+" -ForegroundColor Red
Write-Host "  |          SPORE OS - UNINSTALL CONFIRMATION               |" -ForegroundColor Red
Write-Host "  +----------------------------------------------------------+" -ForegroundColor Red
Write-Host "  |  This will permanently remove (User-space):              |" -ForegroundColor Red
Write-Host "  |    * All user-space binaries and data                    |" -ForegroundColor Red
Write-Host "  |    * Spore Shell and Spore Witness Start Menu shortcuts  |" -ForegroundColor Red
Write-Host "  +----------------------------------------------------------+" -ForegroundColor Red
Write-Host ""

$Confirm = Read-Host "  Type 'yes' to confirm"
if ($Confirm -ne 'yes') { Die "Aborted - you must type exactly: yes" }

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$InstallDir   = Join-Path $env:LOCALAPPDATA 'spore-os'
$BinDir       = Join-Path $InstallDir 'bin'
$DataDir      = $InstallDir
$StartMenuDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Spore OS'

$Nodes = @('spore-shell', 'spore-witness', 'spore-log', 'spore-dialog', 'spore')

# ---------------------------------------------------------------------------
# 1. Stop running daemon and node processes
# ---------------------------------------------------------------------------
Step "Stopping software processes"

$userSpored = Get-Process -Name 'spored' -ErrorAction SilentlyContinue
if ($userSpored) {
    Stop-Process -Name 'spored' -Force -ErrorAction SilentlyContinue
    Success "User daemon stopped"
}

foreach ($node in $Nodes) {
    if (Get-Process -Name $node -ErrorAction SilentlyContinue) {
        Stop-Process -Name $node -Force -ErrorAction SilentlyContinue
        Success "Stopped running process: $node"
    }
}

# ---------------------------------------------------------------------------
# 2. Remove directories
# ---------------------------------------------------------------------------
Step "Removing directories"

if (Test-Path $InstallDir) {
    try {
        Remove-Item -Recurse -Force $InstallDir
        Success "Removed $InstallDir"
    } catch {
        Warn "Could not remove some files in $InstallDir (they may be in use): $_"
    }
} else {
    Warn "$InstallDir not found - skipping"
}

# ---------------------------------------------------------------------------
# 3. Remove Start Menu shortcuts
# ---------------------------------------------------------------------------
Step "Removing Start Menu shortcuts"

foreach ($shortcut in @('Spore Shell', 'Spore Witness')) {
    $target = "$StartMenuDir\$shortcut.lnk"
    if (Test-Path $target) {
        Remove-Item -Force $target
        Success "Removed $target"
    } else {
        Warn "$target not found - skipping"
    }
}

if (Test-Path $StartMenuDir) {
    $remaining = Get-ChildItem $StartMenuDir -ErrorAction SilentlyContinue
    if (-not $remaining) {
        Remove-Item -Force $StartMenuDir
        Success "Removed $StartMenuDir"
    }
}

# ---------------------------------------------------------------------------
# 4. Remove install directories from the user PATH
# ---------------------------------------------------------------------------
Step "Cleaning user PATH"

$currentPath = [System.Environment]::GetEnvironmentVariable('PATH', 'User')
$pathsToRemove = @($InstallDir, $BinDir)
$parts         = $currentPath -split ';' | Where-Object { $_ -ne '' -and $_ -notin $pathsToRemove }
$newPath       = $parts -join ';'

if ($newPath -ne $currentPath) {
    [System.Environment]::SetEnvironmentVariable('PATH', $newPath, 'User')
    Success "Updated user PATH registry"
} else {
    Warn "No Spore OS entries found in user PATH - skipping"
}

# Remove SPORE_DATA_DIR environment variable
[System.Environment]::SetEnvironmentVariable('SPORE_DATA_DIR', $null, 'User')

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host "  Spore OS has been successfully uninstalled." -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host ""
