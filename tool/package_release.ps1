<#
.SYNOPSIS
    Script di packaging e assemblaggio per il rilascio standalone di A.U.R.A. (ZIP Portabile & Manifest di Release).

.PARAMETER Version
    Versione del rilascio (es. "0.1.0" o "1.0.0").
#>
param(
    [string]$Version = "0.1.0"
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " A.U.R.A. Standalone Release Packaging Pipeline" -ForegroundColor Cyan
Write-Host " Versione Rilascio: $Version" -ForegroundColor Cyan
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

# 2. Generazione/Staging dei binari di runtime multi-variante
Write-Host "⚙️ Preparazione runtime multi-variante (build_llama_runtimes.ps1)..." -ForegroundColor Yellow
& "$PSScriptRoot\build_llama_runtimes.ps1" -Version $Version

# 3. Compilazione pacchetto Flutter Release per Windows
Write-Host "🛠️ Compilazione Flutter Windows Release..." -ForegroundColor Yellow
Push-Location "$projectRoot\app"
try {
    flutter build windows --release
} finally {
    Pop-Location
}

$flutterBuildDir = "$projectRoot\app\build\windows\x64\runner\Release"
if (-not (Test-Path "$flutterBuildDir\aura_app.exe")) {
    throw "Build Flutter fallita: aura_app.exe non trovato in $flutterBuildDir"
}

# 4. Assemblaggio layout di rilascio in release/aura-v<Version>-win-x64
$releaseRootDir = "$projectRoot\release"
$bundleDirName = "aura-v$Version-win-x64"
$targetBundleDir = "$releaseRootDir\$bundleDirName"

if (Test-Path $targetBundleDir) {
    Remove-Item -Path $targetBundleDir -Recurse -Force
}
New-Item -ItemType Directory -Path $targetBundleDir -Force | Out-Null

Write-Host "📦 Copia file di build Flutter e dipendenze..." -ForegroundColor Yellow
Copy-Item -Path "$flutterBuildDir\*" -Destination $targetBundleDir -Recurse -Force

Write-Host "📦 Copia directory runtime multi-variante..." -ForegroundColor Yellow
Copy-Item -Path "$projectRoot\runtime" -Destination "$targetBundleDir\runtime" -Recurse -Force

# 5. Generazione THIRD_PARTY_NOTICES.txt
$noticesFile = "$targetBundleDir\THIRD_PARTY_NOTICES.txt"
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

# 6. Generazione SHA256SUMS.txt per tutti i file del bundle
Write-Host "🔒 Calcolo checksum SHA-256 (SHA256SUMS.txt)..." -ForegroundColor Yellow
$sumsFile = "$targetBundleDir\SHA256SUMS.txt"
$allFiles = Get-ChildItem -Path $targetBundleDir -Recurse -File | Where-Object { $_.Name -ne "SHA256SUMS.txt" }

$sumLines = @()
foreach ($f in $allFiles) {
    $hash = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash.ToLower()
    $rel = $f.FullName.Substring($targetBundleDir.Length + 1).Replace("\", "/")
    $sumLines += "$hash  $rel"
}
Set-Content -Path $sumsFile -Value ($sumLines -join "`r`n") -Encoding UTF8

# 7. Generazione release-manifest.json
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
Set-Content -Path "$targetBundleDir\release-manifest.json" -Value $releaseManifestJson -Encoding UTF8

# 8. Archiviazione ZIP portabile
$zipFile = "$releaseRootDir\$bundleDirName.zip"
if (Test-Path $zipFile) {
    Remove-Item -Path $zipFile -Force
}

Write-Host "🤐 Archiviazione ZIP portabile: $zipFile..." -ForegroundColor Yellow
Compress-Archive -Path "$targetBundleDir\*" -DestinationPath $zipFile -CompressionLevel Optimal

Write-Host "==========================================================" -ForegroundColor Green
Write-Host " ✅ Pacchetto di rilascio completato con successo!" -ForegroundColor Green
Write-Host " Bundled Folder: $targetBundleDir" -ForegroundColor Green
Write-Host " Archive ZIP:    $zipFile" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
