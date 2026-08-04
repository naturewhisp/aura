param(
    [string]$Version = "0.1.0",
    [string]$ReleaseDir = "",
    [switch]$RequireInstaller
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " A.U.R.A. Release Asset Integrity Verifier" -ForegroundColor Cyan
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

$bundleDirName = "aura-v$Version-win-x64"
$bundleDir = "$targetReleaseDir\$bundleDirName"
$zipFile = "$targetReleaseDir\$bundleDirName.zip"
$installerFile = "$targetReleaseDir\aura_setup_v$Version.exe"

# 1. Verifica cartella bundle
if (-not (Test-Path $bundleDir)) {
    throw "[FAIL-CLOSED] Cartella bundle non trovata: $bundleDir"
}

# 2. Verifica eseguibile principale
$mainExe = "$bundleDir\aura_app.exe"
if (-not (Test-ValidPeExecutable $mainExe)) {
    throw "[FAIL-CLOSED] Eseguibile principale non valido o assente: $mainExe"
}

# 3. Assenza di file di modello (GGUF, safetensors, bin)
$modelFiles = Get-ChildItem -Path $bundleDir -Recurse -Include "*.gguf", "*.safetensors", "*.model"
if ($modelFiles.Count -gt 0) {
    throw "[FAIL-CLOSED] Trovati file di modello non ammessi nel pacchetto: $($modelFiles.FullName -join ', ')"
}

# 4. Assenza di placeholder di sviluppo
$placeholderLogs = Get-ChildItem -Path $bundleDir -Recurse -Filter "*placeholder*"
if ($placeholderLogs.Count -gt 0) {
    throw "[FAIL-CLOSED] Trovati file placeholder nel pacchetto: $($placeholderLogs.FullName -join ', ')"
}

# 5. Verifica manifest di runtime
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

    # Verification probe con PATH isolato
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

# 6. Verifica file ZIP portable
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

# 7. Verifica Installer se richiesto
if ($RequireInstaller) {
    if (-not (Test-Path $installerFile)) {
        throw "[FAIL-CLOSED] Installer richiesto ma non trovato in: $installerFile"
    }
    if (-not (Test-ValidPeExecutable $installerFile)) {
        throw "[FAIL-CLOSED] Installer generato non e un binario PE valido: $installerFile"
    }
}

Write-Host "==========================================================" -ForegroundColor Green
Write-Host " ✅ Tutte le verifiche di integrita degli asset sono superate!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
