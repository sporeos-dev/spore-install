# Copyright 2026 Matt Harrison
# SPDX-License-Identifier: Apache-2.0

# remove-legacy-install.ps1 -- Removes the pre-machine-service Spore OS layout.
# Run from the account that owns the legacy installation.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost',
    '',
    Justification = 'Interactive removal status must remain visible with color.'
)]
param(
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Die ([string]$Message) { Write-Host "ERROR: $Message" -ForegroundColor Red; exit 1 }

if (-not $env:LOCALAPPDATA) {
    Die 'LOCALAPPDATA is not set.'
}

$LegacyInstallDir = Join-Path $env:LOCALAPPDATA 'spore-os'
$legacyDataDir = [Environment]::GetEnvironmentVariable('SPORE_DATA_DIR', 'User')
$hasLegacyDirectory = Test-Path -LiteralPath $LegacyInstallDir
$hasLegacyDataDir = $legacyDataDir -and $legacyDataDir -ieq $LegacyInstallDir

if (-not $hasLegacyDirectory -and -not $hasLegacyDataDir) {
    Write-Host "No legacy Spore OS user state found for this user."
    exit 0
}

Write-Host 'This permanently removes legacy Spore OS user state.' -ForegroundColor Red
if ($hasLegacyDirectory) {
    Write-Host "  Directory: $LegacyInstallDir" -ForegroundColor Red
}
if ($hasLegacyDataDir) {
    Write-Host "  User environment variable: SPORE_DATA_DIR=$legacyDataDir" -ForegroundColor Red
}
if (-not $Force -and (Read-Host "Type 'yes' to confirm") -ne 'yes') {
    Die 'Aborted.'
}

if ($hasLegacyDirectory) {
    Remove-Item -LiteralPath $LegacyInstallDir -Recurse -Force
}
if ($hasLegacyDataDir) {
    [Environment]::SetEnvironmentVariable('SPORE_DATA_DIR', $null, 'User')
}
Write-Host 'Removed legacy Spore OS user state.' -ForegroundColor Green
