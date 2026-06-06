# Copyright 2026 Matt Harrison
# SPDX-License-Identifier: Apache-2.0

# uninstall.ps1 — Spore OS Windows uninstaller
# Must be run as Administrator.  Requires explicit confirmation before making
# any destructive changes.  All removal steps tolerate already-absent targets.

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
# Must be Administrator
# ---------------------------------------------------------------------------
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Die "uninstall.ps1 must be run as Administrator.  Re-run in an elevated PowerShell."
}

# ---------------------------------------------------------------------------
# Confirmation
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "  +----------------------------------------------------------+" -ForegroundColor Red
Write-Host "  |          SPORE OS - UNINSTALL CONFIRMATION               |" -ForegroundColor Red
Write-Host "  +----------------------------------------------------------+" -ForegroundColor Red
Write-Host "  |  This will permanently remove:                           |" -ForegroundColor Red
Write-Host "  |    * The dev.sporeos.spored service and all CLI node binaries   |" -ForegroundColor Red
Write-Host "  |    * All Spore OS system directories and data            |" -ForegroundColor Red
Write-Host "  |    * The spore service account and group                 |" -ForegroundColor Red
Write-Host "  |    * Spore Shell and Spore Witness Start Menu shortcuts  |" -ForegroundColor Red
Write-Host "  +----------------------------------------------------------+" -ForegroundColor Red
Write-Host ""

$Confirm = Read-Host "  Type 'yes' to confirm"
if ($Confirm -ne 'yes') { Die "Aborted - you must type exactly: yes" }

$InstallDir   = Join-Path $env:ProgramFiles 'spore-os'
$BinDir       = Join-Path $InstallDir 'bin'
$DataDir      = Join-Path $env:ProgramData 'spore-os'
$StartMenuDir = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Spore OS'

$ServiceName  = 'dev.sporeos.spored'
$ServiceUser  = 'spore'
$ServiceGroup = 'Spore OS'

$Nodes = @('spore-shell', 'spore-witness', 'spore-log', 'spore')

# ---------------------------------------------------------------------------
# 1. Stop the Windows service and node processes
# ---------------------------------------------------------------------------
Step "Stopping Windows service ($ServiceName) and node processes"

$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc) {
    if ($svc.Status -eq 'Running') {
        Stop-Service -Name $ServiceName -Force
        Success "Service $ServiceName stopped"
    } else {
        Warn "Service $ServiceName is not running - skipping stop"
    }
} else {
    Warn "Service $ServiceName not found - skipping"
}

foreach ($node in $Nodes) {
    if (Get-Process -Name $node -ErrorAction SilentlyContinue) {
        Step "Stopping running process: $node"
        Stop-Process -Name $node -Force -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# 2. Unregister the service via spored uninstall
# ---------------------------------------------------------------------------
Step "Unregistering Windows service"

$SporedExe = Join-Path $InstallDir 'spored.exe'
if (Test-Path $SporedExe) {
    & $SporedExe uninstall
    if ($LASTEXITCODE -eq 0) {
        Success "spored uninstall completed"
    } else {
        Warn "spored uninstall returned $LASTEXITCODE - attempting manual removal"
        sc.exe delete $ServiceName | Out-Null
        Success "Service $ServiceName removed via sc.exe"
    }
} else {
    Warn "$SporedExe not found - removing service directly"
    if ($svc) {
        sc.exe delete $ServiceName | Out-Null
        Success "Service $ServiceName removed via sc.exe"
    }
}

# ---------------------------------------------------------------------------
# 3. Remove install and data directories
# ---------------------------------------------------------------------------
Step "Removing system directories"

foreach ($path in @($InstallDir, $DataDir)) {
    if (Test-Path $path) {
        Remove-Item -Recurse -Force $path
        Success "Removed $path"
    } else {
        Warn "$path not found - skipping"
    }
}

# ---------------------------------------------------------------------------
# 4. Remove Start Menu shortcuts
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
# 5. Remove install directories from the system PATH
# ---------------------------------------------------------------------------
Step "Cleaning system PATH"

$machinePath   = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine')
$pathsToRemove = @($InstallDir, $BinDir)
$parts         = $machinePath -split ';' | Where-Object { $_ -ne '' -and $_ -notin $pathsToRemove }
$newPath       = $parts -join ';'

if ($newPath -ne $machinePath) {
    [System.Environment]::SetEnvironmentVariable('PATH', $newPath, 'Machine')
    $env:PATH = $newPath
    foreach ($p in $pathsToRemove) {
        if ($machinePath -like "*$p*") { Success "Removed from PATH: $p" }
    }
} else {
    Warn "No Spore OS entries found in PATH - skipping"
}

# ---------------------------------------------------------------------------
# 6. Delete system user and group
# ---------------------------------------------------------------------------
Step "Removing service account and group"

if (Get-LocalUser -Name $ServiceUser -ErrorAction SilentlyContinue) {
    Remove-LocalUser -Name $ServiceUser
    Success "User '$ServiceUser' deleted"
} else {
    Warn "User '$ServiceUser' not found - skipping"
}

if (Get-LocalGroup -Name $ServiceGroup -ErrorAction SilentlyContinue) {
    Remove-LocalGroup -Name $ServiceGroup
    Success "Group '$ServiceGroup' deleted"
} else {
    Warn "Group '$ServiceGroup' not found - skipping"
}

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host "  Spore OS has been successfully uninstalled." -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host ""
