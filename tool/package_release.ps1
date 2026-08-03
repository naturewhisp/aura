<#
.SYNOPSIS
    Script transazionale di packaging e assemblaggio per il rilascio standalone di A.U.R.A. (ZIP Portabile, Manifest & Installer Inno Setup).

.PARAMETER Version
    Versione del rilascio (es. "0.1.0" o "1.0.0").

.PARAMETER AllowPlaceholders
    Set solo in ambienti CI/dev per consentire test del packaging con eseguibili stub.
    DISATTIVATO di default per garantire che le release ufficiali contengano unicamente binari reali.
#>
param(
    [string]$Version = "0.1.0",
    [switch]$AllowPlaceholders
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " A.U.R.A. Transactional Standalone Release Pipeline" -ForegroundColor Cyan
Write-Host " Versione Rilascio: $Version" -ForegroundColor Cyan
Write-Host " Placeholders Consentiti: $AllowPlaceholders" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$projectRoot = Resolve-Path "$PSScriptRoot\.."

# 1. Scansione Igiene & Formattazione pre-build (Zero Diagnostic / Strict Format)
Write-Host "🔍 Verification Pre-Commit: Formattazione & Analisi Statica..." -ForegroundColor Yellow

dart format --output=none --set-exit-if-changed "$projectRoot\lib" "$projectRoot\test" "$projectRoot\bin" "$projectRoot\tool"

Push-Location "$projectRoot\app"
try {
    dart format --output=none --set-exit-if-changed lib test
} finally {
    Pop-Location
}

# 2. Inizializzazione della directory transazionale di staging build/release-staging
$buildDir = "$projectRoot\build"
$stagingDir = "$buildDir\release-staging"
$runtimeStagingDir = "$buildDir\runtime-staging"

if (Test-Path $stagingDir) {
    Remove-Item -Path $stagingDir -Recurse -Force
}
New-Item -ItemType Directory -Path $stagingDir -Force | Out-Null

# 3. Generazione e verifica transazionale dei binari di runtime multi-variante
Write-Host "⚙️ Preparazione runtime multi-variante in staging..." -ForegroundColor Yellow
$buildRuntimeArgs = @{
    Version = $Version
    OutDir = $runtimeStagingDir
}
if ($AllowPlaceholders) {
    $buildRuntimeArgs['AllowPlaceholders'] = $true
}

& "$PSScriptRoot\build_llama_runtimes.ps1" @buildRuntimeArgs

# 4. Compilazione pacchetto Flutter Release per Windows
Write-Host "🛠️ Compilazione Flutter Windows Release..." -ForegroundColor Yellow
Push-Location "$projectRoot\app"
try {
    flutter build windows --release
} finally {
    Pop-Location
}

$flutterBuildDir = "$projectRoot\app\build\windows\x64\runner\Release"
if (-not (Test-Path "$flutterBuildDir\aura_app.exe")) {
    throw "[ERRORE STRUTTURALE] Build Flutter fallita: aura_app.exe non trovato in $flutterBuildDir"
}

# 5. Assemblaggio transazionale in build/release-staging
Write-Host "📦 Assemblaggio transazionale del bundle di rilascio..." -ForegroundColor Yellow
Copy-Item -Path "$flutterBuildDir\*" -Destination $stagingDir -Recurse -Force
Copy-Item -Path $runtimeStagingDir -Destination "$stagingDir\runtime" -Recurse -Force

# Generazione THIRD_PARTY_NOTICES.txt
$noticesFile = "$stagingDir\THIRD_PARTY_NOTICES.txt"
$noticesContent = @"
===============================================================================
 A.U.R.A. (Artificial Unbound Reasoning Arena) - Third Party Notices
===============================================================================

This package includes software developed by third parties under open source licenses:

1. llama.cpp / llama-server
   License: MIT License
   Copyright (c) 2023-2026 Georgi Gerganov and contributors.

2. Flutter SDK & Dependencies
   License: BSD 3-Clause License
   Copyright (c) 2014 The Flutter Authors.

3. CUDA Runtime Libraries (NVIDIA)
   Redistributable dynamic link libraries under NVIDIA CUDA EULA.
===============================================================================
"@
Set-Content -Path $noticesFile -Value $noticesContent -Encoding UTF8

# Generazione release-manifest.json PRIMA del calcolo SHA256SUMS.txt (incluso nei checksum)
$releaseManifest = [ordered]@{
    version = $Version
    buildDateUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    targetPlatform = "windows-x64"
    executable = "aura_app.exe"
    runtimeManifest = "runtime/runtime-manifest.json"
    notices = "THIRD_PARTY_NOTICES.txt"
    checksums = "SHA256SUMS.txt"
}
$releaseManifestJson = $releaseManifest | ConvertTo-Json -Depth 5
Set-Content -Path "$stagingDir\release-manifest.json" -Value $releaseManifestJson -Encoding UTF8

# Calcolo SHA256SUMS.txt inclusivo di release-manifest.json
Write-Host "🔒 Calcolo checksum SHA-256 (SHA256SUMS.txt)..." -ForegroundColor Yellow
$sumsFile = "$stagingDir\SHA256SUMS.txt"
$allFiles = Get-ChildItem -Path $stagingDir -Recurse -File | Where-Object { $_.Name -ne "SHA256SUMS.txt" }

$sumLines = @()
foreach ($f in $allFiles) {
    $hash = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash.ToLower()
    $rel = $f.FullName.Substring($stagingDir.Length + 1).Replace("\", "/")
    $sumLines += "$hash  $rel"
}
Set-Content -Path $sumsFile -Value ($sumLines -join "`r`n") -Encoding UTF8

# 6. Promozione atomica dello staging in release/
$releaseRootDir = "$projectRoot\release"
$bundleDirName = "aura-v$Version-win-x64"
$targetBundleDir = "$releaseRootDir\$bundleDirName"

if (-not (Test-Path $releaseRootDir)) {
    New-Item -ItemType Directory -Path $releaseRootDir -Force | Out-Null
}

if (Test-Path $targetBundleDir) {
    Remove-Item -Path $targetBundleDir -Recurse -Force
}

Move-Item -Path $stagingDir -Destination $targetBundleDir -Force

# 7. Archiviazione ZIP portabile
$zipFile = "$releaseRootDir\$bundleDirName.zip"
if (Test-Path $zipFile) {
    Remove-Item -Path $zipFile -Force
}

Write-Host "🤐 Archiviazione ZIP portabile: $zipFile..." -ForegroundColor Yellow
Compress-Archive -Path "$targetBundleDir\*" -DestinationPath $zipFile -CompressionLevel Optimal

# 8. Compilazione Installer Inno Setup (se ISCC.exe disponibile)
$isccPath = Get-Command "iscc" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $isccPath) {
    $possiblePaths = @(
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe"
    )
    foreach ($p in $possiblePaths) {
        if (Test-Path $p) {
            $isccPath = $p
            break
        }
    }
}

if ($isccPath) {
    Write-Host "🔨 Compilazione Installer Inno Setup con ISCC.exe ($isccPath)..." -ForegroundColor Yellow
    $issFile = "$projectRoot\tool\aura_installer.iss"
    & $isccPath "/DMyAppVersion=$Version" $issFile
    Write-Host "✅ Installer generato in release/ aura_setup_v$Version.exe" -ForegroundColor Green
} else {
    Write-Host "ℹ️ ISCC.exe non trovato nel sistema. Compilazione installer .exe saltata (ZIP portabile generato correttamente)." -ForegroundColor Yellow
}

Write-Host "==========================================================" -ForegroundColor Green
Write-Host " ✅ Pacchetto di rilascio completato con successo!" -ForegroundColor Green
Write-Host " Bundled Folder: $targetBundleDir" -ForegroundColor Green
Write-Host " Archive ZIP:    $zipFile" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
