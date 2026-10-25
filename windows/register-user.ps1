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

function Add-UserPath ([string]$Path) {
    $userPath = [Environment]::GetEnvironmentVariable('PATH', 'User')
    $parts = @($userPath -split ';' | Where-Object { $_ })
    if ($parts | Where-Object { $_ -ieq $Path }) {
        Success "User PATH already contains $Path"
        return
    }
    $updatedPath = (@($parts) + $Path) -join ';'
    [Environment]::SetEnvironmentVariable('PATH', $updatedPath, 'User')
    $env:PATH = $env:PATH + ';' + $Path
    Success "Added to user PATH: $Path"
}

function Enable-PowerShellHints ([string]$IntegrationPath) {
    $documentsDir = [Environment]::GetFolderPath('MyDocuments')
    $profiles = @(
        (Join-Path $documentsDir 'WindowsPowerShell\Profile.ps1'),
        (Join-Path $documentsDir 'PowerShell\Profile.ps1')
    )
    $startMarker = '# >>> Spore terminal hints >>>'
    $endMarker = '# <<< Spore terminal hints <<<'
    $integrationReference = $IntegrationPath.Replace("'", "''")

    foreach ($profilePath in $profiles) {
        $profileDir = Split-Path -Parent $profilePath
        New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
        if (Test-Path -LiteralPath $profilePath) {
            $profile = Get-Content -LiteralPath $profilePath -Raw
            if ($profile.Contains($startMarker)) {
                continue
            }
        }

        Add-Content -LiteralPath $profilePath -Value @(
            '',
            $startMarker,
            ". '$integrationReference'",
            $endMarker
        )
    }
    Success 'Enabled PowerShell Tab hints for spore commands'
}

if (Test-IsAdministrator) {
    Die 'register-user.ps1 must be run from a non-elevated PowerShell session.'
}

$InstallDir = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'spore-os'
$StoreDir = Join-Path $InstallDir 'store'
$HyphaeExe = Join-Path $StoreDir 'hyphae\hyphae.exe'
$PowerShellIntegration = Join-Path $InstallDir 'integrations\powershell.ps1'
$SporeCliDir = Join-Path $StoreDir 'spore'
$ServiceName = 'dev.sporeos.spored'
$CurrentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$CurrentUserSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$HyphaeTaskName = "dev.sporeos.HYPHAE.$CurrentUserSid"
$StartMenuDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Spore OS'

foreach ($requiredPath in @($HyphaeExe, $PowerShellIntegration, (Join-Path $SporeCliDir 'spore.exe'))) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        Die "Machine installation is incomplete; required file is missing: $requiredPath"
    }
}

$service = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if (-not $service -or $service.Status -ne 'Running') {
    Die "SporeD service is not running. Run install-machine.ps1 from an elevated PowerShell session first."
}

Step "Registering Hyphae for $CurrentUser"
$action = New-ScheduledTaskAction -Execute $HyphaeExe -WorkingDirectory (Split-Path -Parent $HyphaeExe)
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $CurrentUser
$principal = New-ScheduledTaskPrincipal -UserId $CurrentUser -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1)
$task = New-ScheduledTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings
Register-ScheduledTask -TaskName $HyphaeTaskName -InputObject $task -Force | Out-Null
Start-ScheduledTask -TaskName $HyphaeTaskName
Success "Hyphae registered as \$HyphaeTaskName"

Step 'Creating user integrations'
Add-UserPath $SporeCliDir
Enable-PowerShellHints $PowerShellIntegration
New-Item -ItemType Directory -Force -Path $StartMenuDir | Out-Null
$shell = New-Object -ComObject WScript.Shell
foreach ($shortcut in @(
    @{ Name = 'Spore Shell'; Binary = (Join-Path $StoreDir 'spore-shell\spore-shell.exe') },
    @{ Name = 'Spore Witness'; Binary = (Join-Path $StoreDir 'spore-witness\spore-witness.exe') }
)) {
    $link = $shell.CreateShortcut((Join-Path $StartMenuDir "$($shortcut.Name).lnk"))
    $link.TargetPath = $shortcut.Binary
    $link.WorkingDirectory = Split-Path $shortcut.Binary
    $link.Save()
}
Success 'Created user shortcuts and terminal integrations'

Write-Host ""
Write-Host 'Spore OS user registration complete. Restart terminal sessions to refresh PATH and PowerShell integration.' -ForegroundColor Green
