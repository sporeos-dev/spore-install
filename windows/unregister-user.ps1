# Copyright 2026 Matt Harrison
# SPDX-License-Identifier: Apache-2.0

param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Step ([string]$Message) { Write-Host ""; Write-Host ">> $Message" -ForegroundColor Cyan }
function Success ([string]$Message) { Write-Host "OK $Message" -ForegroundColor Green }
function Die ([string]$Message) { Write-Host "ERROR: $Message" -ForegroundColor Red; exit 1 }

function Test-IsAdministrator {
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [System.Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Remove-PowerShellHints {
    $documentsDir = [Environment]::GetFolderPath('MyDocuments')
    $profiles = @(
        (Join-Path $documentsDir 'WindowsPowerShell\Profile.ps1'),
        (Join-Path $documentsDir 'PowerShell\Profile.ps1')
    )
    $startMarker = '# >>> Spore terminal hints >>>'
    $endMarker = '# <<< Spore terminal hints <<<'
    $pattern = "(?ms)^$([regex]::Escape($startMarker))\r?\n.*?^$([regex]::Escape($endMarker))\r?\n?"

    foreach ($profilePath in $profiles) {
        if (-not (Test-Path -LiteralPath $profilePath)) {
            continue
        }
        $profile = Get-Content -LiteralPath $profilePath -Raw
        $updatedProfile = [regex]::Replace($profile, $pattern, '')
        if ($updatedProfile -ne $profile) {
            [IO.File]::WriteAllText($profilePath, $updatedProfile, [Text.UTF8Encoding]::new($false))
        }
    }
}

if (Test-IsAdministrator) {
    Die 'unregister-user.ps1 must be run from a non-elevated PowerShell session.'
}

$InstallDir = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'spore-os'
$StoreDir = Join-Path $InstallDir 'store'
$SporeCliDir = Join-Path $StoreDir 'spore'
$HyphaeExe = Join-Path $StoreDir 'hyphae\hyphae.exe'
$UserNodeExecutables = @(
    $HyphaeExe,
    (Join-Path $StoreDir 'spore-shell\spore-shell.exe'),
    (Join-Path $StoreDir 'spore-witness\spore-witness.exe'),
    (Join-Path $StoreDir 'spore-dialog\spore-dialog.exe')
)
$CurrentUserSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$HyphaeTaskName = "dev.sporeos.HYPHAE.$CurrentUserSid"
$StartMenuDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Spore OS'

Step 'Removing Hyphae registration'
$task = Get-ScheduledTask -TaskName $HyphaeTaskName -ErrorAction SilentlyContinue
if ($task) {
    Unregister-ScheduledTask -TaskName $HyphaeTaskName -Confirm:$false
    Success 'Hyphae scheduled task removed'
} else {
    Success 'Hyphae scheduled task was not registered for this user'
}

foreach ($process in @(Get-Process -Name 'hyphae','spore-shell','spore-witness','spore-dialog' -ErrorAction SilentlyContinue)) {
    if ($process.Path -in $UserNodeExecutables) {
        Stop-Process -Id $process.Id -Force
        $process.WaitForExit()
    }
}

Step 'Removing user integrations'
foreach ($shortcut in @('Spore Shell.lnk', 'Spore Witness.lnk')) {
    $path = Join-Path $StartMenuDir $shortcut
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
    }
}
$userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
$updatedPath = @($userPath -split ';' | Where-Object { $_ -and $_ -ine $SporeCliDir }) -join ';'
[Environment]::SetEnvironmentVariable('PATH', $updatedPath, 'User')
Remove-PowerShellHints
Success 'Removed user shortcuts, PATH entry, and PowerShell hints'

Write-Host ""
Write-Host 'Spore OS user unregistration complete.' -ForegroundColor Green
