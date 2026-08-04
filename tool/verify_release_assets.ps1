param(
    [string]$Version = "0.1.0",
    [string]$ReleaseDir = "",
    [switch]$RequireInstaller
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " A.U.R.A. Comprehensive Release Asset Verifier (Fail-Closed)" -ForegroundColor Cyan
Write-Host " Versione: $Version" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$projectRoot = Resolve-Path "$PSScriptRoot\.."
if ([string]::IsNullOrWhiteSpace($ReleaseDir)) {
    $targetReleaseDir = "$projectRoot\release"
} else {
    $targetReleaseDir = $ReleaseDir
}

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

function Test-ValidWavRiffHeader($filePath) {
    if (-not (Test-Path $filePath)) { return $false }
    try {
        $bytes = Get-Content -Path $filePath -Encoding Byte -TotalCount 12 -ErrorAction SilentlyContinue
        # RIFF = 0x52, 0x49, 0x46, 0x46; WAVE = 0x57, 0x41, 0x56, 0x45
        if ($bytes.Length -eq 12 -and $bytes[0] -eq 0x52 -and $bytes[1] -eq 0x49 -and $bytes[2] -eq 0x46 -and $bytes[3] -eq 0x46 -and $bytes[8] -eq 0x57 -and $bytes[9] -eq 0x41 -and $bytes[10] -eq 0x56 -and $bytes[11] -eq 0x45) {
            return $true
        }
    } catch {}
    return $false
}

$bundleDirName = "aura-v$Version-win-x64"
$bundleDir = "$targetReleaseDir\$bundleDirName"
$zipFile = "$targetReleaseDir\$bundleDirName.zip"
$installerFile = "$targetReleaseDir\aura_setup_v$Version.exe"
$releaseSumsFile = "$targetReleaseDir\AURA-$Version-SHA256SUMS.txt"

# 1. Verifica cartella bundle ed eseguibile principale
if (-not (Test-Path $bundleDir)) {
    throw "[FAIL-CLOSED] Cartella bundle non trovata: $bundleDir"
}
$mainExe = "$bundleDir\aura_app.exe"
if (-not (Test-ValidPeExecutable $mainExe)) {
    throw "[FAIL-CLOSED] Eseguibile principale non valido o assente: $mainExe"
}

# 2. Assenza di file di modello e placeholder
$modelFiles = Get-ChildItem -Path $bundleDir -Recurse -Include "*.gguf", "*.safetensors", "*.model"
if ($modelFiles.Count -gt 0) {
    throw "[FAIL-CLOSED] Trovati file di modello non ammessi nel pacchetto: $($modelFiles.FullName -join ', ')"
}
$placeholderLogs = Get-ChildItem -Path $bundleDir -Recurse -Filter "*placeholder*"
if ($placeholderLogs.Count -gt 0) {
    throw "[FAIL-CLOSED] Trovati file placeholder nel pacchetto: $($placeholderLogs.FullName -join ', ')"
}

# 3. Verifica release-manifest.json
$releaseManifestPath = "$targetReleaseDir\release-manifest.json"
if (-not (Test-Path $releaseManifestPath)) {
    throw "[FAIL-CLOSED] release-manifest.json non trovato in $releaseManifestPath"
}
$relManifest = Get-Content -Path $releaseManifestPath -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($relManifest.sourceCommit)) {
    throw "[FAIL-CLOSED] release-manifest.json non contiene sourceCommit"
}
if (-not $relManifest.signedCatalogs) {
    throw "[FAIL-CLOSED] release-manifest.json dichiara signedCatalogs: false"
}

# 4. Verifica runtime-manifest.json e varianti
$runtimeManifestPath = "$bundleDir\runtime\runtime-manifest.json"
if (-not (Test-Path $runtimeManifestPath)) {
    throw "[FAIL-CLOSED] runtime-manifest.json non trovato in: $runtimeManifestPath"
}
$runtimeManifest = Get-Content -Path $runtimeManifestPath -Raw | ConvertFrom-Json
if ($runtimeManifest.variants.Count -lt 3) {
    throw "[FAIL-CLOSED] Meno di 3 varianti runtime nel manifest ($($runtimeManifest.variants.Count))"
}

foreach ($variant in $runtimeManifest.variants) {
    $vId = $variant.id
    $vExe = "$bundleDir\runtime\$($variant.executable.Replace('/', '\'))"
    if (-not (Test-ValidPeExecutable $vExe)) {
        throw "[FAIL-CLOSED] Eseguibile PE non valido per la variante $vId: $vExe"
    }

    $oldPath = $env:PATH
    try {
        $vendorPaths = @()
        if ($variant.vendorDirectories) {
            foreach ($vd in $variant.vendorDirectories) {
                $vp = "$bundleDir\runtime\$($vd.Replace('/', '\'))"
                if (Test-Path $vp) {
                    $vendorPaths += (Resolve-Path $vp).Path
                }
            }
        }
        $wDir = "$bundleDir\runtime\$($variant.workingDirectory.Replace('/', '\'))"
        if (Test-Path $wDir) {
            $wDir = (Resolve-Path $wDir).Path
        }

        $env:PATH = (($vendorPaths + $wDir + $oldPath) -join ';')
        $proc = Start-Process -FilePath $vExe -ArgumentList "--version" -WorkingDirectory $wDir -NoNewWindow -PassThru -Wait -ErrorAction Stop
        if ($proc.ExitCode -ne 0) {
            throw "[FAIL-CLOSED] Probe --version fallita per variante $vId con exit code $($proc.ExitCode)"
        }
    } finally {
        $env:PATH = $oldPath
    }
}

# 5. Verifica audio-manifest.json ed intesita file WAV RIFF Header
$audioManifestPath = "$bundleDir\audio-manifest.json"
if (Test-Path $audioManifestPath) {
    $audioManifest = Get-Content -Path $audioManifestPath -Raw | ConvertFrom-Json
    foreach ($track in $audioManifest.tracks) {
        $audioFile = "$bundleDir\audio\$($track.filename)"
        if (-not (Test-Path $audioFile)) {
            throw "[FAIL-CLOSED] File audio tracciato assente: $audioFile"
        }
        if (-not (Test-ValidWavRiffHeader $audioFile)) {
            throw "[FAIL-CLOSED] File audio non e un archivio WAV RIFF valido: $audioFile"
        }
        $calcHash = (Get-FileHash -Path $audioFile -Algorithm SHA256).Hash.ToLower()
        if ($calcHash -ne $track.sha256.ToLower()) {
            throw "[FAIL-CLOSED] Checksum mismatch su file audio $audioFile"
        }
    }
    Write-Host "✅ Asset audio e manifest verificati con successo!" -ForegroundColor Green
}

# 6. Verifica firma del catalogo modelli model-manifest.json via Dart
$modelManifestPath = "$targetReleaseDir\model-manifest.json"
if (-not (Test-Path $modelManifestPath)) {
    throw "[FAIL-CLOSED] model-manifest.json non trovato in $modelManifestPath"
}
$catalogVerifyResult = & dart run "$projectRoot\tool\catalog\verify_catalog.dart"
if ($LASTEXITCODE -ne 0) {
    throw "[FAIL-CLOSED] Verifica firma del catalogo modelli fallita!"
}
Write-Host "✅ Firma e trust store del catalogo modelli verificati!" -ForegroundColor Green

# 7. Verifica SBOM e THIRD_PARTY_NOTICES
$sbomPath = "$targetReleaseDir\SBOM.spdx.json"
if (-not (Test-Path $sbomPath)) {
    throw "[FAIL-CLOSED] SBOM.spdx.json assente."
}
$sbomJson = Get-Content -Path $sbomPath -Raw | ConvertFrom-Json
if ($sbomJson.spdxVersion -ne "SPDX-2.3") {
    throw "[FAIL-CLOSED] Formato SPDX non valido: $($sbomJson.spdxVersion)"
}

$noticesPath = "$targetReleaseDir\THIRD_PARTY_NOTICES.txt"
if (-not (Test-Path $noticesPath) -or (Get-Item $noticesPath).Length -lt 100) {
    throw "[FAIL-CLOSED] THIRD_PARTY_NOTICES.txt non valido o vuoto."
}

# 8. Verifica file ZIP e checksums di release
if (-not (Test-Path $zipFile)) {
    throw "[FAIL-CLOSED] Archivio ZIP portabile non trovato: $zipFile"
}

$tempExtractDir = "$projectRoot\build\test_extract_portable"
if (Test-Path $tempExtractDir) {
    Remove-Item -Path $tempExtractDir -Recurse -Force
}
Expand-Archive -Path $zipFile -DestinationPath $tempExtractDir -Force
if (-not (Test-ValidPeExecutable "$tempExtractDir\aura_app.exe")) {
    throw "[FAIL-CLOSED] Eseguibile estrapolato da ZIP portabile non valido."
}
Remove-Item -Path $tempExtractDir -Recurse -Force -ErrorAction SilentlyContinue

# 9. Verifica AURA-<version>-SHA256SUMS.txt
if (-not (Test-Path $releaseSumsFile)) {
    throw "[FAIL-CLOSED] File checksum release assente: $releaseSumsFile"
}
$sumLines = Get-Content -Path $releaseSumsFile
foreach ($line in $sumLines) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $parts = $line -split '\s+'
    if ($parts.Length -ge 2) {
        $expHash = $parts[0].Trim().ToLower()
        $relFile = $parts[1].Trim()
        $fullPath = "$targetReleaseDir\$relFile"
        if (Test-Path $fullPath) {
            $actHash = (Get-FileHash -Path $fullPath -Algorithm SHA256).Hash.ToLower()
            if ($expHash -ne $actHash) {
                throw "[FAIL-CLOSED] Checksum mismatch su asset di release $relFile! Atteso: $expHash, Calcolato: $actHash"
            }
        }
    }
}

if ($RequireInstaller) {
    if (-not (Test-Path $installerFile)) {
        throw "[FAIL-CLOSED] Installer richiesto ma non trovato in: $installerFile"
    }
    if (-not (Test-ValidPeExecutable $installerFile)) {
        throw "[FAIL-CLOSED] Installer generato non e un binario PE valido: $installerFile"
    }
}

Write-Host "==========================================================" -ForegroundColor Green
Write-Host " ✅ TUTTE LE VERIFICHE DI SICUREZZA ED INTEGRITA' SONO SUPERATE!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
