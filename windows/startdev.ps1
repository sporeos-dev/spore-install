# Copyright 2026 Matt Harrison
# SPDX-License-Identifier: Apache-2.0

# startdev.ps1 — Start Spore OS local development environment on Windows

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Step    ([string]$msg) { Write-Host ""; Write-Host ">> $msg" -ForegroundColor Cyan }
function Success ([string]$msg) { Write-Host "OK $msg" -ForegroundColor Green }
function Warn    ([string]$msg) { Write-Host "!! $msg" -ForegroundColor Yellow }
function Die     ([string]$msg) { Write-Host "ERROR: $msg" -ForegroundColor Red; exit 1 }

# Validate environment
if (-not $env:DEV) { Die "DEV environment variable is not set.  Aborting." }

$ScriptDir     = $PSScriptRoot
$RepoRoot      = Split-Path -Parent $ScriptDir
$DevDir        = Join-Path $RepoRoot 'dev'
$SocketPath    = 'C:\tmp\spore2.sock'
$SocketDir     = 'C:\tmp'

# Set environment variable for the registry override
$env:SPORE_DATA_DIR = $DevDir

# Verify build has been run
$SporedExe = Join-Path $DevDir 'spored.exe'
if (-not (Test-Path $SporedExe)) { Die "spored.exe not found. Run .\windows\develop.ps1 first!" }

# Ensure directories exist
$DataDir     = Join-Path $DevDir 'data'
$ManifestDir = Join-Path $DevDir 'manifests'
$RunDir      = Join-Path $DevDir 'run'

foreach ($dir in @($DataDir, $ManifestDir, $RunDir, $SocketDir)) {
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
}

# Stop any previously running dev daemon or nodes using Stop-Process
Step "Stopping any running dev processes"
Stop-Process -Name "spored" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "spore-log" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "spore-witness" -Force -ErrorAction SilentlyContinue

if (Test-Path $SocketPath) { Remove-Item -Force $SocketPath }

# Install development node manifests offline
Step "Installing development node manifests"
Get-ChildItem "$DevDir\nodes\*.manifest.spore.yaml" | ForEach-Object {
    & $SporedExe install $_.FullName
    Success "Installed: $($_.Name)"
}

# Start spored
Step "Starting spored on $SocketPath..."
$SporedProc = Start-Process -FilePath $SporedExe -ArgumentList $SocketPath -NoNewWindow -PassThru

# Wait for socket to appear
Success "Waiting for daemon socket to be created..."
for ($i = 0; $i -lt 30; $i++) {
    if (Test-Path $SocketPath) { break }
    Start-Sleep -Milliseconds 100
}

if (-not (Test-Path $SocketPath)) {
    Stop-Process -Id $SporedProc.Id -Force -ErrorAction SilentlyContinue
    Die "Daemon failed to start or create socket at $SocketPath"
}
Success "Daemon is listening!"

# Start core logging background nodes
Step "Starting core nodes..."

$LogExe = Join-Path $DevDir "bin\spore-log.exe"
$WitnessExe = Join-Path $DevDir "bin\spore-witness.exe"

$LogProc = Start-Process -FilePath $LogExe -ArgumentList $SocketPath -NoNewWindow -PassThru
Success "Started spore-log (PID $($LogProc.Id))"

$WitnessProc = Start-Process -FilePath $WitnessExe -ArgumentList $SocketPath -NoNewWindow -PassThru
Success "Started spore-witness (PID $($WitnessProc.Id))"

# Define cleanup block
$Cleanup = {
    Write-Host ""
    Write-Host ">> Shutting down development environment..." -ForegroundColor Cyan
    Stop-Process -Id $WitnessProc.Id -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $LogProc.Id -Force -ErrorAction SilentlyContinue
    Stop-Process -Id $SporedProc.Id -Force -ErrorAction SilentlyContinue
    if (Test-Path $SocketPath) { Remove-Item -Force $SocketPath }
    Write-Host "OK All processes stopped. Cleaned up $SocketPath." -ForegroundColor Green
}

# Wait for process termination
Write-Host ""
Write-Host "===========================================================" -ForegroundColor Green
Write-Host "  Development environment is running!" -ForegroundColor Green
Write-Host "  Press Ctrl+C to stop all processes." -ForegroundColor Green
Write-Host "===========================================================" -ForegroundColor Green
Write-Host "Try running spore or spore-shell in another terminal:" -ForegroundColor Cyan
Write-Host "  `$env:DEV = `"$env:DEV`""
Write-Host "  `$env:SPORE_DATA_DIR = `"$DevDir`""
Write-Host "  & `"$DevDir\bin\spore-shell`" `"$SocketPath`""
Write-Host ""

try {
    while (-not $SporedProc.HasExited) {
        Start-Sleep -Seconds 1
    }
} finally {
    & $Cleanup
}
