# Copyright 2026 Matt Harrison
# SPDX-License-Identifier: Apache-2.0

# install.ps1 — Spore OS Windows installer
# Must be run from the dist\ directory (or alongside dist\ contents) as Administrator.
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

# ---------------------------------------------------------------------------
# Must be Administrator
# ---------------------------------------------------------------------------
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Die "install.ps1 must be run as Administrator.  Re-run in an elevated PowerShell."
}

$ScriptDir = $PSScriptRoot
$DistDir   = $ScriptDir   # install.ps1 lives inside dist\ after build

# ---------------------------------------------------------------------------
# Detect system architecture
# ---------------------------------------------------------------------------
$Arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$InstallDir   = Join-Path $env:ProgramFiles 'spore-os'
$BinDir       = Join-Path $InstallDir 'bin'
$DataDir      = Join-Path $env:ProgramData 'spore-os'
$LogDir       = Join-Path $DataDir 'logs'
$HubDir       = Join-Path $DataDir 'hub'
$ManifestDir  = Join-Path $DataDir 'manifests'
$RunDir       = Join-Path $DataDir 'run'
$StartMenuDir = Join-Path $env:ProgramData 'Microsoft\Windows\Start Menu\Programs\Spore OS'

$ServiceName  = 'dev.sporeos.spored'
$ServiceUser  = 'spore'
$ServiceGroup = 'Spore OS'

$Nodes = @('spore-shell', 'spore-witness', 'spore-log', 'spore-dialog', 'spore')

# ---------------------------------------------------------------------------
# Helper: grant SeServiceLogonRight to a local user via secedit
# ---------------------------------------------------------------------------
function Grant-LogonAsService ([string]$Username) {
    $tempInf = [System.IO.Path]::GetTempFileName()
    $tempDb  = [System.IO.Path]::GetTempFileName() + '.sdb'

    try {
        secedit /export /cfg $tempInf /areas USER_RIGHTS /quiet

        $sid = (New-Object System.Security.Principal.NTAccount($Username)).Translate(
            [System.Security.Principal.SecurityIdentifier]).Value

        $content = Get-Content $tempInf -Raw

        if ($content -match 'SeServiceLogonRight\s*=') {
            # Only append if the SID is not already present
            if ($content -notmatch [regex]::Escape("*$sid")) {
                $content = $content -replace '(SeServiceLogonRight\s*=\s*)(\S.*)', "`$1`$2,*$sid"
            }
        } else {
            # SeServiceLogonRight line is absent; insert it under [Privilege Rights]
            $content = $content -replace '(\[Privilege Rights\])', "`$1`r`nSeServiceLogonRight = *$sid"
        }

        $content | Set-Content $tempInf -Encoding Unicode
        secedit /import /cfg $tempInf /db $tempDb /areas USER_RIGHTS /quiet
        secedit /configure /db $tempDb /areas USER_RIGHTS /quiet
    } finally {
        Remove-Item $tempInf, $tempDb -ErrorAction SilentlyContinue
    }
}

# ---------------------------------------------------------------------------
# 1. Create system group and user
# ---------------------------------------------------------------------------
Step "Creating system user and group: $ServiceGroup / $ServiceUser"

if (-not (Get-LocalGroup -Name $ServiceGroup -ErrorAction SilentlyContinue)) {
    New-LocalGroup -Name $ServiceGroup -Description 'Spore OS service group'
    Success "Group '$ServiceGroup' created"
} else {
    Warn "Group '$ServiceGroup' already exists - skipping"
}

$userExists = [bool](Get-LocalUser -Name $ServiceUser -ErrorAction SilentlyContinue)
$svcExists  = [bool](Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)

# We need a password if the user does not exist, OR if the service does not exist (so we have to configure it)
$needPassword = (-not $userExists) -or (-not $svcExists)

if ($needPassword) {
    # Generate a cryptographically random password for the service account
    $rng      = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $bytes    = New-Object byte[] 32
    $rng.GetBytes($bytes)
    $script:ServicePassword = [Convert]::ToBase64String($bytes)
    $secPass  = ConvertTo-SecureString $script:ServicePassword -AsPlainText -Force
} else {
    $script:ServicePassword = $null
}

if (-not $userExists) {
    New-LocalUser -Name $ServiceUser `
                  -Password $secPass `
                  -Description 'Spore OS service account' `
                  -AccountNeverExpires `
                  -PasswordNeverExpires
    Add-LocalGroupMember -Group $ServiceGroup -Member $ServiceUser
    Success "User '$ServiceUser' created and added to '$ServiceGroup'"

    Grant-LogonAsService $ServiceUser
    Success "Granted SeServiceLogonRight to '$ServiceUser'"
} else {
    Warn "User '$ServiceUser' already exists - skipping creation"
    if ($needPassword) {
         Set-LocalUser -Name $ServiceUser -Password $secPass
         Success "Reset password for existing user '$ServiceUser' to configure service"
    }
}

# ---------------------------------------------------------------------------
# 2. Create required system directories
# ---------------------------------------------------------------------------
Step "Creating system directories"

$Dirs = @(
    (Join-Path $DataDir 'data'),
    $HubDir,
    $ManifestDir,
    $RunDir,
    $LogDir,
    $BinDir
)

foreach ($dir in $Dirs) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    # Grant the service account full control over all data directories
    $acl  = Get-Acl $dir
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $ServiceUser,
        'FullControl',
        'ContainerInherit,ObjectInherit',
        'None',
        'Allow')
    $acl.SetAccessRule($rule)
    Set-Acl -Path $dir -AclObject $acl
    Success $dir
}

# ---------------------------------------------------------------------------
# 3. Install binaries
# ---------------------------------------------------------------------------
Step "Installing binaries to $InstallDir"

# Stop the dev.sporeos.spored service if running to unlock binaries
$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running') {
    Step "Stopping $ServiceName service to unlock binaries"
    Stop-Service -Name $ServiceName -Force
    Success "Service stopped"
}

# Stop any running node processes to unlock binaries
foreach ($node in $Nodes) {
    if (Get-Process -Name $node -ErrorAction SilentlyContinue) {
        Step "Stopping running process: $node"
        Stop-Process -Name $node -Force -ErrorAction SilentlyContinue
    }
}

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

$acl  = Get-Acl "$HubDir\spored.manifest.spore.yaml"
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $ServiceUser, 'ReadAndExecute', 'None', 'None', 'Allow')
$acl.SetAccessRule($rule)
Set-Acl -Path "$HubDir\spored.manifest.spore.yaml" -AclObject $acl

Success "Hub manifest installed at $HubDir"

# ---------------------------------------------------------------------------
# 5. Add install directories to the system PATH
# ---------------------------------------------------------------------------
Step "Updating system PATH"

$machinePath = [System.Environment]::GetEnvironmentVariable('PATH', 'Machine')
$changed     = $false

foreach ($p in @($InstallDir, $BinDir)) {
    if ($machinePath -notlike "*$p*") {
        $machinePath += ";$p"
        $changed = $true
        Success "Added to PATH: $p"
    } else {
        Warn "Already in PATH: $p - skipping"
    }
}

if ($changed) {
    [System.Environment]::SetEnvironmentVariable('PATH', $machinePath, 'Machine')
    $env:PATH = $machinePath
}

# ---------------------------------------------------------------------------
# 6. Register Windows service and start it
# ---------------------------------------------------------------------------
Step "Registering Windows service ($ServiceName)"

$svcExists = [bool](Get-Service -Name $ServiceName -ErrorAction SilentlyContinue)

if (-not $svcExists) {
    & "$InstallDir\spored.exe" install
    if ($LASTEXITCODE -ne 0) { Die "spored install returned $LASTEXITCODE" }
    Success "Windows service registered"

    # Configure service to run as the dedicated service account when the user
    # was freshly created/configured and a password is available
    if ($script:ServicePassword) {
        sc.exe config $ServiceName "obj= .\$ServiceUser" "password= $script:ServicePassword" | Out-Null
        Success "Service account set to '.\$ServiceUser'"
    }
} else {
    Warn "Service $ServiceName already registered - skipping"
}

$svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
if ($svc -and $svc.Status -eq 'Running') {
    Warn "Service $ServiceName is already running - skipping start"
} else {
    Start-Service -Name $ServiceName
    Success "Service $ServiceName started"
}

# ---------------------------------------------------------------------------
# 7. Install node manifests, then restart daemon
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

    Step "Restarting daemon to load manifests"
    Restart-Service -Name $ServiceName -Force
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
