# Copyright 2026 Matt Harrison
# SPDX-License-Identifier: Apache-2.0

#Requires -RunAsAdministrator

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Step ([string]$Message) { Write-Host ""; Write-Host ">> $Message" -ForegroundColor Cyan }
function Success ([string]$Message) { Write-Host "OK $Message" -ForegroundColor Green }
function Warn ([string]$Message) { Write-Host "!! $Message" -ForegroundColor Yellow }
function Die ([string]$Message) { Write-Host "ERROR: $Message" -ForegroundColor Red; exit 1 }

$ScriptDir = $PSScriptRoot
$DistDir = $ScriptDir
$Arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
$InstallDir = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'spore-os'
$DataDir = Join-Path $InstallDir 'data'
$StoreDir = Join-Path $InstallDir 'store'
$LogDir = Join-Path $InstallDir 'logs'
$IntegrationsDir = Join-Path $InstallDir 'integrations'
$PowerShellIntegration = Join-Path $IntegrationsDir 'powershell.ps1'
$RegistryFile = Join-Path $InstallDir 'nodes.registry.yaml'
$ServiceName = 'dev.sporeos.spored'
$Nodes = @('spore-shell', 'spore-witness', 'spore-log', 'spore', 'spore-dialog', 'hyphae', 'store')

function Remove-SporeDService {
    $existingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $existingService) {
        return
    }

    if ($existingService.Status -ne 'Stopped') {
        Stop-Service -Name $ServiceName -Force
    }
    $existingService.Dispose()

    & sc.exe delete $ServiceName | Out-Null
    if ($LASTEXITCODE -notin @(0, 1060)) { Die "Failed to remove the existing $ServiceName service" }

    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        & sc.exe query $ServiceName *> $null
        if ($LASTEXITCODE -eq 1060) {
            return
        }
        Start-Sleep -Seconds 1
    }
    Die "Timed out waiting for the existing $ServiceName service to be removed"
}

function Remove-LegacyHyphaeTask {
    $legacyTask = Get-ScheduledTask -TaskName 'dev.sporeos.agent' -ErrorAction SilentlyContinue
    if (-not $legacyTask) {
        return
    }

    $installedHyphaeExe = Join-Path $StoreDir 'hyphae\hyphae.exe'
    if (-not (@($legacyTask.Actions | Where-Object { $_.Execute -ieq $installedHyphaeExe }).Count -gt 0)) {
        Warn 'Existing dev.sporeos.agent task does not target the installed Hyphae executable; leaving it unchanged'
        return
    }

    Unregister-ScheduledTask -TaskName 'dev.sporeos.agent' -Confirm:$false
    Success 'Removed legacy root Hyphae task'
}

function Set-RestrictedDirectoryAcl ([string]$Path) {
    & icacls.exe $Path /inheritance:r /grant:r `
        'SYSTEM:(OI)(CI)F' `
        'BUILTIN\Administrators:(OI)(CI)F' `
        'NT AUTHORITY\LOCAL SERVICE:(OI)(CI)F' | Out-Null
    if ($LASTEXITCODE -ne 0) { Die "Failed to secure $Path" }
}

function Set-StoreAcl ([string]$Path) {
    & icacls.exe $Path /inheritance:r /grant:r `
        'SYSTEM:(OI)(CI)F' `
        'BUILTIN\Administrators:(OI)(CI)F' `
        'NT AUTHORITY\LOCAL SERVICE:(OI)(CI)F' `
        'BUILTIN\Users:(OI)(CI)RX' | Out-Null
    if ($LASTEXITCODE -ne 0) { Die "Failed to secure $Path" }
}

function Set-RootAcl ([string]$Path) {
    & icacls.exe $Path /inheritance:r /grant:r `
        'SYSTEM:(OI)(CI)F' `
        'BUILTIN\Administrators:(OI)(CI)F' `
        'NT AUTHORITY\LOCAL SERVICE:(OI)(CI)F' `
        'BUILTIN\Users:RX' | Out-Null
    if ($LASTEXITCODE -ne 0) { Die "Failed to secure $Path" }
}

function Set-RestrictedFileAcl ([string]$Path) {
    & icacls.exe $Path /inheritance:r /grant:r `
        'SYSTEM:F' `
        'BUILTIN\Administrators:F' `
        'NT AUTHORITY\LOCAL SERVICE:F' | Out-Null
    if ($LASTEXITCODE -ne 0) { Die "Failed to secure $Path" }
}

foreach ($requiredPath in @(
    "$DistDir\$Arch\spored.exe",
    "$DistDir\spored.manifest.spore.yaml",
    "$DistDir\nodes",
    "$DistDir\integrations\powershell.ps1",
    "$DistDir\$Arch\bin"
)) {
    if (-not (Test-Path $requiredPath)) {
        Die "Required installation asset is missing: $requiredPath"
    }
}

Step "Stopping the existing SporeD service"
Remove-SporeDService
Remove-LegacyHyphaeTask

Step "Creating protected machine directories"
foreach ($directory in @($InstallDir, $DataDir, $StoreDir, $LogDir, $IntegrationsDir)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
}
Set-RootAcl $InstallDir
Set-RestrictedDirectoryAcl $DataDir
Set-StoreAcl $StoreDir
Set-RestrictedDirectoryAcl $LogDir
Set-StoreAcl $IntegrationsDir
Success "Created and secured $InstallDir"

Step "Installing SporeD and node binaries"
$SporedExe = Join-Path $InstallDir 'spored.exe'
Copy-Item "$DistDir\$Arch\spored.exe" $SporedExe -Force
Copy-Item "$DistDir\spored.manifest.spore.yaml" (Join-Path $InstallDir 'spored.manifest.spore.yaml') -Force
Set-RestrictedFileAcl $SporedExe
Set-RestrictedFileAcl (Join-Path $InstallDir 'spored.manifest.spore.yaml')

foreach ($node in $Nodes) {
    $source = "$DistDir\$Arch\bin\$node.exe"
    if (-not (Test-Path $source)) { Die "Required node binary is missing: $source" }
    $nodeStoreDir = Join-Path $StoreDir $node
    New-Item -ItemType Directory -Force -Path $nodeStoreDir | Out-Null
    Copy-Item $source (Join-Path $nodeStoreDir "$node.exe") -Force
}
Set-StoreAcl $StoreDir
Copy-Item "$DistDir\integrations\powershell.ps1" $PowerShellIntegration -Force
Set-StoreAcl $IntegrationsDir
Success "Installed machine-owned binaries"

Step "Writing the protected node registry"
$registryLines = @(
    '# Spore OS Node Registry — managed by installer/spored, do not edit manually',
    'version: 1',
    'nodes:'
)
$manifests = @(Get-ChildItem "$DistDir\nodes\*.manifest.spore.yaml" -ErrorAction SilentlyContinue)
if ($manifests.Count -eq 0) { Die "No node manifests found in $DistDir\nodes" }

foreach ($manifest in $manifests) {
    $nodeName = $manifest.Name -replace '\.manifest\.spore\.yaml$', ''
    $nodeStoreDir = Join-Path $StoreDir $nodeName
    $destManifest = Join-Path $nodeStoreDir $manifest.Name
    $binaryPath = Join-Path $nodeStoreDir "$nodeName.exe"
    if (-not (Test-Path $binaryPath)) { Die "Manifest has no installed binary: $binaryPath" }
    Copy-Item $manifest.FullName $destManifest -Force

    $manifestHash = (Get-FileHash -Path $destManifest -Algorithm SHA256).Hash.ToLower()
    $binaryHash = (Get-FileHash -Path $binaryPath -Algorithm SHA256).Hash.ToLower()
    $manifestId = (Select-String -Path $destManifest -Pattern '^id:\s*(.+)').Matches[0].Groups[1].Value.Trim()
    $manifestName = (Select-String -Path $destManifest -Pattern '^name:\s*(.+)').Matches[0].Groups[1].Value.Trim()
    $registryLines += "  - name: $manifestName"
    $registryLines += "    id: $manifestId"
    $registryLines += "    manifest: $($destManifest -replace '\\', '/')"
    $registryLines += "    checksum: 'sha256:$manifestHash'"
    $registryLines += "    binary: $($binaryPath -replace '\\', '/')"
    $registryLines += "    binaryChecksum: 'sha256:$binaryHash'"
}
[IO.File]::WriteAllLines($RegistryFile, $registryLines, [Text.UTF8Encoding]::new($false))
Set-RestrictedFileAcl $RegistryFile
Set-StoreAcl $StoreDir
Success "Node registry written to $RegistryFile"

Step "Registering and starting SporeD"
& $SporedExe install
if ($LASTEXITCODE -ne 0) { Die "SporeD service installation failed" }
Start-Service -Name $ServiceName
Start-Sleep -Seconds 2
if ((Get-Service -Name $ServiceName).Status -ne 'Running') { Die "SporeD service did not start" }
Success "SporeD is running as LocalService"

Write-Host ""
Write-Host "Spore OS machine installation complete. Run register-user.ps1 from each user's non-elevated PowerShell session." -ForegroundColor Green
exit 0
