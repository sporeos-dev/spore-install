# Copyright 2026 Matt Harrison
# SPDX-License-Identifier: Apache-2.0

# reinstall.ps1 -- Spore OS Windows development reinstall helper.
# Unregisters the signed-in developer, removes the machine installation,
# rebuilds, reinstalls the machine components, and registers that developer.

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingWriteHost',
    '',
    Justification = 'Interactive installer status must remain visible with color.'
)]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Step ([string]$Message) { Write-Host ""; Write-Host ">> $Message" -ForegroundColor Cyan }
function Success ([string]$Message) { Write-Host "OK $Message" -ForegroundColor Green }
function Warn ([string]$Message) { Write-Host "!! $Message" -ForegroundColor Yellow }
function Die ([string]$Message) { Write-Host "ERROR: $Message" -ForegroundColor Red; exit 1 }

function Test-IsAdministrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Invoke-ElevatedScript ([string]$Path, [string]$AdditionalArguments = '') {
    $outputPath = Join-Path $env:TEMP "spore-elevated-$([guid]::NewGuid()).log"
    $command = "& `"$Path`" $AdditionalArguments *> `"$outputPath`"; exit `$LASTEXITCODE"
    $argumentList = "-NoProfile -ExecutionPolicy Bypass -Command `"$command`""

    $process = Start-Process -FilePath 'powershell.exe' -Verb RunAs -Wait -PassThru -ArgumentList $argumentList
    try {
        if ($process.ExitCode -ne 0) {
            if (Test-Path -LiteralPath $outputPath) {
                Get-Content -LiteralPath $outputPath | Write-Host
            }
            Die "Elevated script failed: $Path (exit code $($process.ExitCode))"
        }
    } finally {
        if (Test-Path -LiteralPath $outputPath) {
            Remove-Item -LiteralPath $outputPath -Force
        }
    }
}

if (Test-IsAdministrator) {
    Die 'reinstall.ps1 must be run from a non-elevated PowerShell session.'
}

$ScriptDir = $PSScriptRoot
$RepoRoot = Split-Path -Parent $ScriptDir
$DistDir = Join-Path $RepoRoot 'dist'
$UninstallScript = Join-Path $DistDir 'uninstall-machine.ps1'
$BuildScript = Join-Path $ScriptDir 'build.ps1'
$InstallScript = Join-Path $DistDir 'install-machine.ps1'
$RegisterUserScript = Join-Path $DistDir 'register-user.ps1'
$UnregisterUserScript = Join-Path $DistDir 'unregister-user.ps1'

if (-not (Test-Path -LiteralPath $BuildScript)) {
    Die "Required script is missing: $BuildScript"
}

if (Test-Path -LiteralPath $UnregisterUserScript) {
    Step 'Unregistering the current user'
    & $UnregisterUserScript
    if (-not $?) {
        Die "User unregistration failed: $UnregisterUserScript"
    }
    Success 'Current user unregistered'
} else {
    Step 'Skipping user unregistration'
    Warn "No prior distribution user unregistration script found at $UnregisterUserScript"
}

if (Test-Path -LiteralPath $UninstallScript) {
    Step 'Uninstalling the current installation'
    Invoke-ElevatedScript $UninstallScript '-Force'
    Success 'Current installation removed'
} else {
    Step 'Skipping uninstall'
    Warn "No prior distribution uninstall script found at $UninstallScript"
}

Step 'Building a fresh distribution'
& $BuildScript

if (-not (Test-Path -LiteralPath $InstallScript) -or -not (Test-Path -LiteralPath $RegisterUserScript)) {
    Die "Build did not produce the required installation scripts"
}

Step 'Installing the fresh machine distribution'
Invoke-ElevatedScript $InstallScript

Step 'Registering the current user'
& $RegisterUserScript
if (-not $?) {
    Die "User registration failed: $RegisterUserScript"
}

Write-Host ""
Write-Host 'Spore OS reinstall complete.' -ForegroundColor Green
