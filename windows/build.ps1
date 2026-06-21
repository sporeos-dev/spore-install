# Copyright 2026 Matt Harrison
# SPDX-License-Identifier: Apache-2.0

# build.ps1 — Spore OS Windows CI/CD build script
# Compiles all binaries for both amd64 and arm64 and stages them in dist\.
# Does NOT require elevation.  Requires the DEV environment variable to be set.

param(
    [Parameter(Position=0)]
    [string]$Mode = ""
)

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
# Validate environment
# ---------------------------------------------------------------------------
if (-not $env:DEV) { Die "DEV environment variable is not set.  Aborting." }

$ScriptDir = $PSScriptRoot
$RepoRoot  = Split-Path -Parent $ScriptDir
$DistDir   = Join-Path $RepoRoot 'dist'

$Nodes = @('spore-shell', 'spore-witness', 'spore-log', 'spore')
$Archs = @('amd64', 'arm64')

# ---------------------------------------------------------------------------
# Prepare dist\ layout
# ---------------------------------------------------------------------------
Step "Preparing dist\ directory"
if (Test-Path $DistDir) { Remove-Item -Recurse -Force $DistDir }
foreach ($arch in $Archs) {
    New-Item -ItemType Directory -Force -Path "$DistDir\$arch\bin" | Out-Null
}
New-Item -ItemType Directory -Force -Path "$DistDir\nodes" | Out-Null
Success "dist\ created at $DistDir"

# ---------------------------------------------------------------------------
# Helper: build Windows binaries for both target architectures.
# Must be called from within the Go project directory.
# Usage: Build-WindowsBinaries <output-base-name>
# ---------------------------------------------------------------------------
function Build-WindowsBinaries ([string]$BaseName) {
    $savedGoos   = $env:GOOS
    $savedGoarch = $env:GOARCH

    foreach ($arch in $Archs) {
        Write-Host "    Building $arch..."
        $env:GOOS   = 'windows'
        $env:GOARCH = $arch
        & go build -o "${BaseName}_${arch}.exe" .
        if ($LASTEXITCODE -ne 0) {
            $env:GOOS   = $savedGoos
            $env:GOARCH = $savedGoarch
            Die "Build failed for $BaseName ($arch)"
        }
    }

    $env:GOOS   = $savedGoos
    $env:GOARCH = $savedGoarch
}

# ---------------------------------------------------------------------------
# 1. Build spored daemon
# ---------------------------------------------------------------------------
Step "Building spored daemon"

$SporedDir = Join-Path $env:DEV 'spore-os\spored'
if (-not (Test-Path $SporedDir)) { Die "spored source not found at $SporedDir" }

Push-Location $SporedDir
try {
    Write-Host "  Running tests..."
    & go test ./... -count=1
    if ($LASTEXITCODE -ne 0) { Die "spored tests failed - aborting build" }

    Build-WindowsBinaries 'spored'

    foreach ($arch in $Archs) {
        Move-Item "spored_${arch}.exe" "$DistDir\$arch\spored.exe" -Force
    }
    Copy-Item 'spored.manifest.spore.yaml' "$DistDir\spored.manifest.spore.yaml"
} finally {
    Pop-Location
}
Success 'spored -> dist\{amd64,arm64}\spored.exe'

# ---------------------------------------------------------------------------
# 2. Build CLI nodes
# ---------------------------------------------------------------------------
Step "Building CLI nodes"

foreach ($node in $Nodes) {
    Write-Host "  > $node"
    $NodeDir = Join-Path $env:DEV "spore-core-nodes\$node"
    if (-not (Test-Path $NodeDir)) { Die "Node source not found at $NodeDir" }

    Push-Location $NodeDir
    try {
        & go test ./... -count=1
        if ($LASTEXITCODE -ne 0) { Die "$node tests failed - aborting build" }

        Build-WindowsBinaries $node

        foreach ($arch in $Archs) {
            Move-Item "${node}_${arch}.exe" "$DistDir\$arch\bin\${node}.exe" -Force
        }
        Copy-Item "${node}.manifest.spore.yaml" "$DistDir\nodes\${node}.manifest.spore.yaml"
    } finally {
        Pop-Location
    }
}
Success 'nodes -> dist\{amd64,arm64}\bin\'

# ---------------------------------------------------------------------------
# 3. Stage installer scripts
# ---------------------------------------------------------------------------
Step "Staging installer scripts"
Copy-Item "$ScriptDir\install.ps1"   "$DistDir\install.ps1"
Copy-Item "$ScriptDir\uninstall.ps1" "$DistDir\uninstall.ps1"
Success "install.ps1 and uninstall.ps1 -> dist\"

# ---------------------------------------------------------------------------
# 4. Write SHA-256 checksums for all binaries
# ---------------------------------------------------------------------------
Step "Computing SHA-256 checksums"
$checksumFile = Join-Path $DistDir 'checksums.sha256'
$lines = [System.Collections.Generic.List[string]]::new()

foreach ($arch in $Archs) {
    $hash = Get-FileHash "$DistDir\$arch\spored.exe" -Algorithm SHA256
    $lines.Add("$($hash.Hash.ToLower())  $arch/spored.exe")

    Get-ChildItem "$DistDir\$arch\bin\*.exe" | Sort-Object Name | ForEach-Object {
        $h   = Get-FileHash $_.FullName -Algorithm SHA256
        $rel = $_.FullName.Substring($DistDir.Length + 1).Replace('\', '/')
        $lines.Add("$($h.Hash.ToLower())  $rel")
    }
}

$lines | Set-Content $checksumFile -Encoding UTF8
Success "checksums.sha256 written"

# ---------------------------------------------------------------------------
# 5. Package release archive (if requested)
# ---------------------------------------------------------------------------
if ($Mode -eq "release") {
    Step "Packaging release archive"
    $archivePath = Join-Path $RepoRoot "spore-os-install-windows.zip"
    if (Test-Path $archivePath) { Remove-Item -Force $archivePath }
    Compress-Archive -Path "$DistDir" -DestinationPath "$archivePath" -Force
    Success "Release archive created: spore-os-install-windows.zip"
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host "  Build complete!  dist\ contents:" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Green
Get-ChildItem -Recurse -File $DistDir | Sort-Object FullName | ForEach-Object {
    $rel = $_.FullName.Substring($DistDir.Length + 1)
    Write-Host "  $rel" -ForegroundColor Green
}
Write-Host ""
