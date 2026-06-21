# Copyright 2026 Matt Harrison
# SPDX-License-Identifier: Apache-2.0

# develop.ps1 — Spore OS Windows development build script
# Compiles all binaries for the host architecture with isDev=true and stages them in dev\.
# Does NOT require elevation.  Requires the DEV environment variable to be set.

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
$DevDir    = Join-Path $RepoRoot 'dev'

$Nodes = @('spore-shell', 'spore-witness', 'spore-log', 'spore')

$ClientGo = Join-Path $env:DEV "spore-client-libs\go\client.go"
$SporedMainGo = Join-Path $env:DEV "spore-os\spored\main.go"

# ---------------------------------------------------------------------------
# Helper: temporarily enable/disable isDev in third party & daemon repos
# ---------------------------------------------------------------------------
function Enable-IsDev {
    Step "Setting {const isDev = true} in source files prior to build"
    if (-not (Test-Path $ClientGo)) { Die "client.go not found at $ClientGo" }
    if (-not (Test-Path $SporedMainGo)) { Die "main.go not found at $SporedMainGo" }

    $clientContent = Get-Content $ClientGo -Raw
    $clientContent = $clientContent -replace 'const isDev = false', 'const isDev = true'
    Set-Content $ClientGo $clientContent -NoNewline -Encoding UTF8

    $sporedContent = Get-Content $SporedMainGo -Raw
    $sporedContent = $sporedContent -replace 'const isDev = false', 'const isDev = true'
    Set-Content $SporedMainGo $sporedContent -NoNewline -Encoding UTF8

    Success "isDev=true set in client.go and main.go"
}

function Disable-IsDev {
    Step "Restoring {const isDev = false} in source files"
    if (Test-Path $ClientGo) {
        $clientContent = Get-Content $ClientGo -Raw
        $clientContent = $clientContent -replace 'const isDev = true', 'const isDev = false'
        Set-Content $ClientGo $clientContent -NoNewline -Encoding UTF8
    }
    if (Test-Path $SporedMainGo) {
        $sporedContent = Get-Content $SporedMainGo -Raw
        $sporedContent = $sporedContent -replace 'const isDev = true', 'const isDev = false'
        Set-Content $SporedMainGo $sporedContent -NoNewline -Encoding UTF8
    }
    Success "isDev=false restored in source files"
}

try {
    Enable-IsDev

    # ---------------------------------------------------------------------------
    # Prepare dev\ layout
    # ---------------------------------------------------------------------------
    Step "Preparing dev\ directory"
    if (Test-Path $DevDir) { Remove-Item -Recurse -Force $DevDir }
    New-Item -ItemType Directory -Force -Path "$DevDir\bin" | Out-Null
    New-Item -ItemType Directory -Force -Path "$DevDir\nodes" | Out-Null
    Success "dev\ created at $DevDir"

    # ---------------------------------------------------------------------------
    # 1. Build spored daemon
    # ---------------------------------------------------------------------------
    Step "Building spored daemon for development"

    $SporedDir = Join-Path $env:DEV 'spore-os\spored'
    if (-not (Test-Path $SporedDir)) { Die "spored source not found at $SporedDir" }

    Push-Location $SporedDir
    try {
        Write-Host "  Running tests..."
        & go test ./... -count=1
        if ($LASTEXITCODE -ne 0) { Die "spored tests failed - aborting build" }

        Write-Host "  Building host architecture..."
        & go build -o spored.exe .
        if ($LASTEXITCODE -ne 0) { Die "spored build failed" }

        Move-Item "spored.exe" "$DevDir\spored.exe" -Force
        Copy-Item 'spored.manifest.spore.yaml' "$DevDir\spored.manifest.spore.yaml"
    } finally {
        Pop-Location
    }
    Success 'spored -> dev\spored.exe'

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

            Write-Host "  Building $node..."
            & go build -o "${node}.exe" .
            if ($LASTEXITCODE -ne 0) { Die "$node build failed" }

            Move-Item "${node}.exe" "$DevDir\bin\${node}.exe" -Force
            Copy-Item "${node}.manifest.spore.yaml" "$DevDir\nodes\${node}.manifest.spore.yaml"
        } finally {
            Pop-Location
        }
    }
    Success 'nodes -> dev\bin\'

    # ---------------------------------------------------------------------------
    # 3. Write SHA-256 checksums for all binaries
    # ---------------------------------------------------------------------------
    Step "Computing SHA-256 checksums"
    $checksumFile = Join-Path $DevDir 'checksums.sha256'
    $lines = [System.Collections.Generic.List[string]]::new()

    $hash = Get-FileHash "$DevDir\spored.exe" -Algorithm SHA256
    $lines.Add("$($hash.Hash.ToLower())  spored.exe")

    Get-ChildItem "$DevDir\bin\*.exe" | Sort-Object Name | ForEach-Object {
        $h   = Get-FileHash $_.FullName -Algorithm SHA256
        $rel = $_.FullName.Substring($DevDir.Length + 1).Replace('\', '/')
        $lines.Add("$($h.Hash.ToLower())  $rel")
    }

    $lines | Set-Content $checksumFile -Encoding UTF8
    Success "checksums.sha256 written"

} finally {
    Disable-IsDev
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ("=" * 60) -ForegroundColor Green
Write-Host "  Development Build complete!  dev\ contents:" -ForegroundColor Green
Write-Host ("=" * 60) -ForegroundColor Green
Get-ChildItem -Recurse -File $DevDir | Sort-Object FullName | ForEach-Object {
    $rel = $_.FullName.Substring($DevDir.Length + 1)
    Write-Host "  $rel" -ForegroundColor Green
}
Write-Host ""
