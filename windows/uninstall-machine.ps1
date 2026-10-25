# Copyright 2026 Matt Harrison
# SPDX-License-Identifier: Apache-2.0

#Requires -RunAsAdministrator

param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Step ([string]$Message) { Write-Host ""; Write-Host ">> $Message" -ForegroundColor Cyan }
function Success ([string]$Message) { Write-Host "OK $Message" -ForegroundColor Green }
function Warn ([string]$Message) { Write-Host "!! $Message" -ForegroundColor Yellow }
function Die ([string]$Message) { Write-Host "ERROR: $Message" -ForegroundColor Red; exit 1 }

$InstallDir = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'spore-os'
$DataDir = Join-Path $InstallDir 'data'
$StoreDir = Join-Path $InstallDir 'store'
$LogDir = Join-Path $InstallDir 'logs'
$ServiceName = 'dev.sporeos.spored'
$SporedExe = Join-Path $InstallDir 'spored.exe'

function Remove-SporeDService {
    $service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $service) {
        Warn "SporeD service is not registered"
        return
    }

    if ($service.Status -ne 'Stopped') {
        Stop-Service -Name $ServiceName -Force
    }
    $service.Dispose()

    & sc.exe delete $ServiceName | Out-Null
    if ($LASTEXITCODE -notin @(0, 1060)) { Die "Failed to remove $ServiceName" }

    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        & sc.exe query $ServiceName *> $null
        if ($LASTEXITCODE -eq 1060) {
            Success "SporeD service removed"
            return
        }
        Start-Sleep -Seconds 1
    }
    Die "Timed out waiting for $ServiceName to be removed"
}

Write-Host ""
Write-Host "This removes the SporeD service and machine-installed binaries." -ForegroundColor Red
Write-Host "Authoritative data remains at $DataDir." -ForegroundColor Red
if (-not $Force -and (Read-Host "Type 'yes' to confirm") -ne 'yes') { Die "Aborted" }

Step "Stopping and removing SporeD"
Remove-SporeDService

Step "Removing machine-installed binaries"
foreach ($path in @(
    $StoreDir,
    $LogDir,
    (Join-Path $InstallDir 'integrations'),
    (Join-Path $InstallDir 'spored.exe'),
    (Join-Path $InstallDir 'spored.manifest.spore.yaml'),
    (Join-Path $InstallDir 'nodes.registry.yaml'),
    (Join-Path $InstallDir 'spore.sock')
)) {
    if (Test-Path $path) {
        try {
            Remove-Item -LiteralPath $path -Recurse -Force
        } catch {
            Die "Failed to remove ${path}: $($_.Exception.Message)"
        }
    }
}
if (Test-Path $InstallDir) {
    $remaining = Get-ChildItem -LiteralPath $InstallDir -Force
    if ($remaining.Count -eq 0) {
        Remove-Item -LiteralPath $InstallDir -Force
    }
}
Success "Removed machine-installed binaries; preserved $DataDir"

Write-Host ""
Write-Host "Spore OS machine uninstall complete. Each user can run unregister-user.ps1 to remove their integrations." -ForegroundColor Green
exit 0
