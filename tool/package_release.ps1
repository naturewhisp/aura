param(
    [string]$Version = "0.1.0",
    [string]$Channel = "beta",
    [string]$ReleaseKind = "candidate",
    [string]$ReleaseTag = "",
    [switch]$RequireInstaller,
    [string]$WorkflowRunId = "",
    [string]$WorkflowRunAttempt = "1",
    [string]$SourceRef = "",
    [string]$SourceBranch = ""
)

$ErrorActionPreference = "Stop"

function Invoke-NativeCommand([scriptblock]$Command, [string]$Description) {
    & $Command
    $code = $LASTEXITCODE
    if ($code -ne 0) {
        throw "[FAIL-CLOSED] $Description fallito con exit code $code"
    }
}

if ([string]::IsNullOrWhiteSpace($ReleaseTag)) {
    $ReleaseTag = "v$Version"
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " A.U.R.A. Transactional Standalone Release Pipeline" -ForegroundColor Cyan
Write-Host " Versione: $Version | Tag: $ReleaseTag | Canale: $Channel | Tipo: $ReleaseKind" -ForegroundColor Cyan
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

Invoke-NativeCommand { dart format --output=none --set-exit-if-changed "$projectRoot\lib" "$projectRoot\test" "$projectRoot\bin" "$projectRoot\tool" } "Dart format check core"

Push-Location "$projectRoot\app"
try {
    Invoke-NativeCommand { dart format --output=none --set-exit-if-changed lib test } "Dart format check app"
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
Invoke-NativeCommand { & "$PSScriptRoot\build_llama_runtimes.ps1" -Version $Version -OutDir $runtimeStagingDir } "Staging runtime multi-variante"

# 4. Compilazione pacchetto Flutter Release per Windows
Write-Host "Compilazione Flutter Windows Release..." -ForegroundColor Yellow
Push-Location "$projectRoot\app"
try {
    Invoke-NativeCommand { flutter build windows --release } "Flutter build windows --release"
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

# Copia degli asset audio di distribuzione
$audioDistDir = "$projectRoot\distribution\audio"
if (Test-Path $audioDistDir) {
    Write-Host "Copia asset audio di distribuzione..." -ForegroundColor Yellow
    $audioStagingDir = "$stagingDir\audio"
    New-Item -ItemType Directory -Path $audioStagingDir -Force | Out-Null
    Copy-Item -Path "$audioDistDir\*" -Destination $audioStagingDir -Recurse -Force
    Copy-Item -Path "$audioDistDir\audio-manifest.json" -Destination "$stagingDir\audio-manifest.json" -Force
}

# Generazione e firma del catalogo modelli (FAIL-CLOSED)
Write-Host "Generazione e firma del catalogo modelli..." -ForegroundColor Yellow
$modelManifestFile = "$stagingDir\model-manifest.json"
Invoke-NativeCommand { dart run "$PSScriptRoot\catalog\sign_catalog.dart" --out-catalog $modelManifestFile } "Firma ed auto-verifica del catalogo modelli"

if (-not (Test-Path $modelManifestFile)) {
    throw "[FAIL-CLOSED] model-manifest.json non generato."
}

# Estrazione keyId e calcolo SHA-256 del catalogo firmato
$modelManifestJson = Get-Content -Path $modelManifestFile -Raw | ConvertFrom-Json
$catalogKeyId = $modelManifestJson.signedPayload.keyId
$catalogDigest = (Get-FileHash -Path $modelManifestFile -Algorithm SHA256).Hash.ToLower()

# Generazione SBOM SPDX 2.3
Write-Host "Generazione SBOM SPDX 2.3 JSON..." -ForegroundColor Yellow
$sbomPath = "$stagingDir\SBOM.spdx.json"
Invoke-NativeCommand { dart run "$PSScriptRoot\generate_sbom.dart" $Version $sbomPath } "Generazione SBOM SPDX 2.3"

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

# Recupero versione Flutter, Dart e metadati runtime
$flutterVer = (flutter --version | Select-Object -First 1).Trim()
$dartVer = (dart --version 2>&1 | Select-Object -First 1).Trim()
$sourceCommit = try { (git rev-parse HEAD).Trim() } catch { "unknown" }

# Lettura llama.cpp metadata da tool/runtime/llama-runtime-lock.json o acquisition-metadata.json
$lockPath = "$projectRoot\tool\runtime\llama-runtime-lock.json"
$acqMetaPath = "$projectRoot\runtime\acquisition-metadata.json"
$llamaCppVersion = "b10256"
$llamaCppCommit = "6c8dcaa7ae41fa9f4aa2b3b68ee82cb8b2a03632"
if (Test-Path $lockPath) {
    try {
        $lockJson = Get-Content -Path $lockPath -Raw | ConvertFrom-Json
        if ($lockJson.llamaCppTag) { $llamaCppVersion = $lockJson.llamaCppTag }
        if ($lockJson.llamaCppCommit) { $llamaCppCommit = $lockJson.llamaCppCommit }
    } catch {}
} elseif (Test-Path $acqMetaPath) {
    try {
        $acqJson = Get-Content -Path $acqMetaPath -Raw | ConvertFrom-Json
        if ($acqJson.llamaCppTag) { $llamaCppVersion = $acqJson.llamaCppTag }
        if ($acqJson.llamaCppCommit) { $llamaCppCommit = $acqJson.llamaCppCommit }
    } catch {}
}

if ([string]::IsNullOrWhiteSpace($SourceRef)) {
    $SourceRef = try { (git symbolic-ref -q HEAD).Trim() } catch { "refs/heads/fase6" }
}
if ($SourceRef.StartsWith("refs/tags/")) {
    $SourceBranch = $null
} elseif ([string]::IsNullOrWhiteSpace($SourceBranch)) {
    $SourceBranch = try { (git rev-parse --abbrev-ref HEAD).Trim() } catch { "fase6" }
}

# Generazione release-manifest.json PRIMA del calcolo SHA256SUMS.txt
$releaseManifest = [ordered]@{
    schemaVersion = 1
    appVersion = $Version
    channel = $Channel
    releaseKind = $ReleaseKind
    sourceCommit = $sourceCommit
    sourceRef = $SourceRef
    sourceBranch = $SourceBranch
    tag = $ReleaseTag
    workflowRunId = $WorkflowRunId
    workflowRunAttempt = [int]$WorkflowRunAttempt
    buildTimestampUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    targetPlatform = "windows-x64"
    flutterVersion = $flutterVer
    dartVersion = $dartVer
    innoSetupVersion = "Inno Setup 6"
    llamaCppVersion = $llamaCppVersion
    llamaCppSourceCommit = $llamaCppCommit
    runtimeSetId = "aura-runtime-v$Version"
    runtimeVariantIds = @("win-x64-cuda", "win-x64-vulkan", "win-x64-cpu-avx2")
    audioSetId = "aura.windows.release.v1"
    catalogDigests = @{
        "model-manifest.json" = $catalogDigest
    }
    catalogSignatureKeyId = $catalogKeyId
    sbomFile = "SBOM.spdx.json"
    checksumsFile = "AURA-$Version-SHA256SUMS.txt"
    installerFile = "aura_setup_v$Version.exe"
    portableFile = "aura-v$Version-win-x64.zip"
    signedCatalogs = $true
    authenticodeSigned = $false
    modelsBundled = $false
}
$releaseManifestJson = $releaseManifest | ConvertTo-Json -Depth 5
Set-Content -Path "$stagingDir\release-manifest.json" -Value $releaseManifestJson -Encoding UTF8

# Calcolo AURA-<Version>-SHA256SUMS.txt inclusivo di release-manifest.json
Write-Host "Calcolo checksum SHA-256 (AURA-$Version-SHA256SUMS.txt)..." -ForegroundColor Yellow
$sumsFileName = "AURA-$Version-SHA256SUMS.txt"
$sumsFile = "$stagingDir\$sumsFileName"
$allFiles = Get-ChildItem -Path $stagingDir -Recurse -File | Where-Object { $_.Name -ne $sumsFileName }

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

# Copy standalone manifest, checksums, sbom, and notices to release/ root for release upload
Copy-Item -Path "$targetBundleDir\release-manifest.json" -Destination "$releaseRootDir\release-manifest.json" -Force
Copy-Item -Path "$targetBundleDir\runtime\runtime-manifest.json" -Destination "$releaseRootDir\runtime-manifest.json" -Force
if (Test-Path "$targetBundleDir\audio-manifest.json") {
    Copy-Item -Path "$targetBundleDir\audio-manifest.json" -Destination "$releaseRootDir\audio-manifest.json" -Force
}
if (Test-Path "$targetBundleDir\model-manifest.json") {
    Copy-Item -Path "$targetBundleDir\model-manifest.json" -Destination "$releaseRootDir\model-manifest.json" -Force
}
Copy-Item -Path "$targetBundleDir\SBOM.spdx.json" -Destination "$releaseRootDir\SBOM.spdx.json" -Force
Copy-Item -Path "$targetBundleDir\THIRD_PARTY_NOTICES.txt" -Destination "$releaseRootDir\THIRD_PARTY_NOTICES.txt" -Force

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
    Invoke-NativeCommand { & $isccPath "/DMyAppVersion=$Version" $issFile } "Compilazione Inno Setup ISCC"
    if (-not (Test-Path $setupInstallerFile)) {
        throw "[FAIL-CLOSED] Compilazione Inno Setup terminata ma l'eseguibile $setupInstallerFile non e stato creato."
    }
    if (-not (Test-ValidPeExecutable $setupInstallerFile)) {
        throw "[FAIL-CLOSED] L'installer generato $setupInstallerFile non e un eseguibile Windows PE valido."
    }
    Write-Host "✅ Installer generato e verificato con successo: $setupInstallerFile" -ForegroundColor Green
} else {
    if ($RequireInstaller) {
        throw "[FAIL-CLOSED] Parametro -RequireInstaller specificato ma ISCC.exe non e stato trovato nel sistema."
    }
    Write-Host "ISCC.exe non trovato nel sistema. Compilazione installer .exe saltata (ZIP portabile generato correttamente)." -ForegroundColor Yellow
}

# 10. Calcolo SHA256SUMS.txt per gli ASSET DI RELEASE in release/
Write-Host "Calcolo checksum per gli asset di GitHub Release..." -ForegroundColor Yellow
$relSumsFile = "$releaseRootDir\AURA-$Version-SHA256SUMS.txt"
$releaseAssets = Get-ChildItem -Path $releaseRootDir -File | Where-Object { $_.Name -ne "AURA-$Version-SHA256SUMS.txt" }
$relSumLines = @()
foreach ($ra in $releaseAssets) {
    $rHash = (Get-FileHash -Path $ra.FullName -Algorithm SHA256).Hash.ToLower()
    $relSumLines += "$rHash  $($ra.Name)"
}
Set-Content -Path $relSumsFile -Value ($relSumLines -join "`r`n") -Encoding UTF8

Write-Host "==========================================================" -ForegroundColor Green
Write-Host " Pacchetto di rilascio completato con successo!" -ForegroundColor Green
Write-Host " Bundled Folder: $targetBundleDir" -ForegroundColor Green
Write-Host " Archive ZIP:    $zipFile" -ForegroundColor Green
Write-Host " Release Checksums: $relSumsFile" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
