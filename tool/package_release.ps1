# Script transazionale di packaging e assemblaggio per il rilascio standalone di A.U.R.A. (ZIP Portabile, Manifest & Installer Inno Setup).
param(
    [string]$Version = "0.1.0"
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " A.U.R.A. Transactional Standalone Release Pipeline" -ForegroundColor Cyan
Write-Host " Versione Rilascio: $Version" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$projectRoot = Resolve-Path "$PSScriptRoot\.."

function Test-ValidPeExecutable($filePath) {
    if (-not (Test-Path $filePath)) { return $false }
    try {
        $stream = [System.IO.File]::OpenRead($filePath)
        $b0 = $stream.ReadByte()
        $b1 = $stream.ReadByte()
        $len = $stream.Length
        $stream.Close()
        if ($len -gt 1000 -and $b0 -eq 77 -and $b1 -eq 90) {
            return $true
        }
    } catch {}
    return $false
}

# 1. Scansione Igiene e Formattazione pre-build (Zero Diagnostic / Strict Format)
Write-Host "Verification Pre-Commit: Formattazione e Analisi Statica..." -ForegroundColor Yellow

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

# 3. Generazione transazionale dei binari di runtime multi-variante reali (senza placeholder)
Write-Host "Preparazione runtime multi-variante reali in staging..." -ForegroundColor Yellow
& "$PSScriptRoot\build_llama_runtimes.ps1" -Version $Version -OutDir $runtimeStagingDir

# 4. Compilazione pacchetto Flutter Release per Windows
Write-Host "Compilazione Flutter Windows Release..." -ForegroundColor Yellow
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
Write-Host "Assemblaggio transazionale del bundle di rilascio..." -ForegroundColor Yellow
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
Write-Host "Calcolo checksum SHA-256 (SHA256SUMS.txt)..." -ForegroundColor Yellow
$sumsFile = "$stagingDir\SHA256SUMS.txt"
$allFiles = Get-ChildItem -Path $stagingDir -Recurse -File | Where-Object { $_.Name -ne "SHA256SUMS.txt" }

$sumLines = @()
foreach ($f in $allFiles) {
    $hash = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash.ToLower()
    $rel = $f.FullName.Substring($stagingDir.Length + 1).Replace("\", "/")
    $sumLines += "$hash  $rel"
}
Set-Content -Path $sumsFile -Value ($sumLines -join "`r`n") -Encoding UTF8

# 6. Validazioni pre-promozione (Parse Manifest, SHA-256 Integrity, PE Header, --version Probe con PATH Vendor & License Check)
Write-Host "Esecuzione verifiche di sicurezza pre-promozione..." -ForegroundColor Yellow

$manifestPath = "$stagingDir\runtime\runtime-manifest.json"
if (-not (Test-Path $manifestPath)) {
    throw "[FAIL-CLOSED] runtime-manifest.json non trovato in staging."
}

$manifestJson = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json
foreach ($variant in $manifestJson.variants) {
    $vId = $variant.id
    $vExe = "$stagingDir\runtime\$($variant.executable.Replace('/', '\'))"

    if (-not (Test-ValidPeExecutable $vExe)) {
        throw "[FAIL-CLOSED] Eseguibile variante $vId non e un binario PE valido: $vExe"
    }

    Write-Host "  Probe --version per la variante $vId (con PATH vendor isolato)..." -ForegroundColor Gray
    $oldPath = $env:PATH
    try {
        $vendorPaths = @()
        if ($variant.vendorDirectories) {
            foreach ($vd in $variant.vendorDirectories) {
                $vp = "$stagingDir\runtime\$($vd.Replace('/', '\'))"
                if (Test-Path $vp) {
                    $vendorPaths += (Resolve-Path $vp).Path
                }
            }
        }
        $wDir = "$stagingDir\runtime\$($variant.workingDirectory.Replace('/', '\'))"
        if (Test-Path $wDir) {
            $wDir = (Resolve-Path $wDir).Path
        }

        $env:PATH = (($vendorPaths + $wDir + $oldPath) -join ';')

        $proc = Start-Process -FilePath $vExe -ArgumentList "--version" -WorkingDirectory $wDir -NoNewWindow -PassThru -Wait -ErrorAction Stop
        if ($proc.ExitCode -ne 0) {
            throw "[FAIL-CLOSED] Probe --version fallita per la variante $vId con ExitCode $($proc.ExitCode)"
        }
    } catch {
        $err = $_.Exception.Message
        throw "[FAIL-CLOSED] Impossibile eseguire probe per la variante $vId : $err"
    } finally {
        $env:PATH = $oldPath
    }

    foreach ($fileEntry in $variant.files) {
        $fPath = "$stagingDir\runtime\$($fileEntry.path.Replace('/', '\'))"
        if (-not (Test-Path $fPath)) {
            throw "[FAIL-CLOSED] File tracciato nel manifest assente: $fPath"
        }
        $calcHash = (Get-FileHash -Path $fPath -Algorithm SHA256).Hash.ToLower()
        if ($calcHash -ne $fileEntry.sha256.ToLower()) {
            throw "[FAIL-CLOSED] Checksum mismatch su $fPath! Atteso: $($fileEntry.sha256), Calcolato: $calcHash"
        }
    }
}

if (-not (Test-Path "$stagingDir\THIRD_PARTY_NOTICES.txt")) {
    throw "[FAIL-CLOSED] THIRD_PARTY_NOTICES.txt non presente nel bundle."
}

Write-Host "Verifiche di sicurezza superate con successo!" -ForegroundColor Green

# 7. Promozione atomica dello staging in release/ (con backup transazionale e rollback)
$releaseRootDir = "$projectRoot\release"
$bundleDirName = "aura-v$Version-win-x64"
$targetBundleDir = "$releaseRootDir\$bundleDirName"
$backupBundleDir = "$releaseRootDir\$bundleDirName-backup"

if (-not (Test-Path $releaseRootDir)) {
    New-Item -ItemType Directory -Path $releaseRootDir -Force | Out-Null
}

if (Test-Path $targetBundleDir) {
    if (Test-Path $backupBundleDir) {
        Remove-Item -Path $backupBundleDir -Recurse -Force
    }
    Move-Item -Path $targetBundleDir -Destination $backupBundleDir -Force
}

try {
    Move-Item -Path $stagingDir -Destination $targetBundleDir -Force
    if (Test-Path $backupBundleDir) {
        Remove-Item -Path $backupBundleDir -Recurse -Force
    }
} catch {
    if (Test-Path $backupBundleDir) {
        Move-Item -Path $backupBundleDir -Destination $targetBundleDir -Force
    }
    throw "[FAIL-CLOSED] Spostamento atomico del bundle in release/ fallito: $_"
}

# 8. Archiviazione ZIP portabile
$zipFile = "$releaseRootDir\$bundleDirName.zip"
if (Test-Path $zipFile) {
    Remove-Item -Path $zipFile -Force
}

Write-Host "Archiviazione ZIP portabile: $zipFile..." -ForegroundColor Yellow
Compress-Archive -Path "$targetBundleDir\*" -DestinationPath $zipFile -CompressionLevel Optimal

# 9. Compilazione Installer Inno Setup (se ISCC.exe disponibile)
$isccPath = Get-Command "iscc" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source
if (-not $isccPath) {
    $possiblePaths = @(
        "$env:LocalAppData\Programs\Inno Setup 6\ISCC.exe",
        "C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
        "C:\Program Files\Inno Setup 6\ISCC.exe"
    )
    foreach ($p in $possiblePaths) {
        if ($p -and (Test-Path $p)) {
            $isccPath = $p
            break
        }
    }
}

$setupInstallerFile = "$releaseRootDir\aura_setup_v$Version.exe"

if ($isccPath) {
    Write-Host "Compilazione Installer Inno Setup con ISCC.exe ($isccPath)..." -ForegroundColor Yellow
    $issFile = "$projectRoot\tool\aura_installer.iss"
    & $isccPath "/DMyAppVersion=$Version" $issFile
    if (-not (Test-Path $setupInstallerFile)) {
        throw "[FAIL-CLOSED] Compilazione Inno Setup terminata ma l'eseguibile $setupInstallerFile non e stato creato."
    }
    if (-not (Test-ValidPeExecutable $setupInstallerFile)) {
        throw "[FAIL-CLOSED] L'installer generato $setupInstallerFile non e un eseguibile Windows PE valido."
    }
    Write-Host "✅ Installer generato e verificato con successo: $setupInstallerFile" -ForegroundColor Green
} else {
    Write-Host "ISCC.exe non trovato nel sistema. Compilazione installer .exe saltata (ZIP portabile generato correttamente)." -ForegroundColor Yellow
}

Write-Host "==========================================================" -ForegroundColor Green
Write-Host " Pacchetto di rilascio completato con successo!" -ForegroundColor Green
Write-Host " Bundled Folder: $targetBundleDir" -ForegroundColor Green
Write-Host " Archive ZIP:    $zipFile" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
