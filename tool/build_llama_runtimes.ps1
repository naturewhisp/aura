<#
.SYNOPSIS
    Script di staging e preparazione delle varianti di runtime llama-server per A.U.R.A.

.PARAMETER Version
    Versione del pacchetto di rilascio (es. "0.1.0" o "1.0.0").

.PARAMETER OutDir
    Directory di destinazione dello staging per il runtime (di default build/runtime-staging).

.PARAMETER AllowPlaceholders
    Attiva la generazione di placeholder di test per ambienti di sviluppo headless/CI senza GPU.
    ATTENZIONE: Questo flag non deve MAI essere utilizzato per le build ufficiali di rilascio!
#>
param(
    [string]$Version = "0.1.0",
    [string]$OutDir = "",
    [switch]$AllowPlaceholders,
    [string]$SourceCommit = ""
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " A.U.R.A. Llama Runtime Staging & Multi-Variant Builder" -ForegroundColor Cyan
Write-Host " Versione: $Version" -ForegroundColor Cyan
Write-Host " Placeholders Consentiti: $AllowPlaceholders" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$projectRoot = Resolve-Path "$PSScriptRoot\.."
if ([string]::IsNullOrWhiteSpace($OutDir)) {
    $targetRuntimeRoot = "$projectRoot\build\runtime-staging"
} else {
    $targetRuntimeRoot = $OutDir
}
if (Test-Path $targetRuntimeRoot) {
    Remove-Item -Path $targetRuntimeRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $targetRuntimeRoot -Force | Out-Null

$binRoot = "$targetRuntimeRoot\bin"

# Lettura metadati di acquisizione runtime da tool/runtime/llama-runtime-lock.json o acquisition-metadata.json
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

if ([string]::IsNullOrWhiteSpace($SourceCommit)) {
    $SourceCommit = $llamaCppCommit
}

# Definizione varianti ufficiali
$variants = @(
    @{
        id = "win-x64-cuda"
        accel = "cuda"
        arch = "x64"
        cpuFeatures = @("avx2", "fma")
        backendCaps = @("cuda12")
        exec = "bin/win-x64-cuda/llama-server.exe"
        workDir = "bin/win-x64-cuda"
        vendorDirs = @("bin/win-x64-cuda/vendor")
        dir = "$binRoot\win-x64-cuda"
        vendorDir = "$binRoot\win-x64-cuda\vendor"
    },
    @{
        id = "win-x64-vulkan"
        accel = "vulkan"
        arch = "x64"
        cpuFeatures = @("avx2")
        backendCaps = @("vulkan")
        exec = "bin/win-x64-vulkan/llama-server.exe"
        workDir = "bin/win-x64-vulkan"
        vendorDirs = @("bin/win-x64-vulkan/vendor")
        dir = "$binRoot\win-x64-vulkan"
        vendorDir = "$binRoot\win-x64-vulkan\vendor"
    },
    @{
        id = "win-x64-cpu-avx2"
        accel = "cpu"
        arch = "x64"
        cpuFeatures = @("avx2", "fma")
        backendCaps = @()
        exec = "bin/win-x64-cpu-avx2/llama-server.exe"
        workDir = "bin/win-x64-cpu-avx2"
        vendorDirs = @()
        dir = "$binRoot\win-x64-cpu-avx2"
        vendorDir = ""
    }
)

foreach ($v in $variants) {
    if (-not (Test-Path $v.dir)) {
        New-Item -ItemType Directory -Path $v.dir -Force | Out-Null
    }
    if ($v.vendorDir -ne "" -and -not (Test-Path $v.vendorDir)) {
        New-Item -ItemType Directory -Path $v.vendorDir -Force | Out-Null
    }
}

function Test-IsPEExecutable([string]$filePath) {
    if (-not (Test-Path $filePath)) { return $false }
    try {
        $stream = [System.IO.File]::OpenRead($filePath)
        try {
            if ($stream.Length -lt 2) {
                return $false
            }
            $firstByte = $stream.ReadByte()
            $secondByte = $stream.ReadByte()
            return ($firstByte -eq 0x4D -and $secondByte -eq 0x5A)
        } finally {
            $stream.Dispose()
        }
    } catch {
        return $false
    }
}

# Verifica o popolamento degli eseguibili per ogni variante
foreach ($v in $variants) {
    $exePath = "$($v.dir)\llama-server.exe"
    
    # Se esiste un file runtime pre-esistente nella root del repo, sincronizzalo nello staging
    $sourceRepoExe = "$projectRoot\runtime\bin\$($v.id)\llama-server.exe"
    if (-not (Test-Path $exePath) -and (Test-Path $sourceRepoExe)) {
        Copy-Item -Path "$projectRoot\runtime\bin\$($v.id)\*" -Destination $v.dir -Recurse -Force
    }

    # Se la variante è win-x64-cuda, include le DLL vendor dinamiche CUDA 12 per garantire esecuzione out-of-the-box su macchine pulite
    if ($v.id -eq "win-x64-cuda" -and -not (Test-Path "$($v.vendorDir)\cublas64_12.dll")) {
        $cudaCandidates = @()
        $cudaToolkitRoot = "C:\Program Files\NVIDIA GPU Computing Toolkit\CUDA"
        if (Test-Path $cudaToolkitRoot) {
            Get-ChildItem -Path $cudaToolkitRoot -Directory | ForEach-Object {
                $binDir = "$($_.FullName)\bin"
                if (Test-Path "$binDir\cublas64_12.dll") { $cudaCandidates += $binDir }
            }
        }
        $lmVendor = "$env:USERPROFILE\.lmstudio\extensions\backends\vendor"
        if (Test-Path $lmVendor) {
            Get-ChildItem -Path $lmVendor -Directory | Where-Object { $_.Name -like "*cuda*" } | ForEach-Object {
                if (Test-Path "$($_.FullName)\cublas64_12.dll") { $cudaCandidates += $_.FullName }
            }
        }
        if ($cudaCandidates.Count -gt 0) {
            $chosenVendor = $cudaCandidates[0]
            Write-Host "Inclusione librerie vendor dinamiche CUDA 12 da $chosenVendor in $($v.vendorDir)..." -ForegroundColor Green
            Get-ChildItem -Path $chosenVendor -Filter "*.dll" | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination $v.vendorDir -Force
            }
        }
    }

    if (-not (Test-Path $exePath)) {
        if ($AllowPlaceholders) {
            Write-Host "⚠️ PLACEHOLDER DI SVILUPPO creato per $($v.id): $exePath" -ForegroundColor Yellow
            # Scrive header MZ minimo per superare i controlli fisici di sviluppo
            $mzHeader = [byte[]]@(0x4D, 0x5A, 0x90, 0x00, 0x03, 0x00, 0x00, 0x00)
            [System.IO.File]::WriteAllBytes($exePath, $mzHeader)
        } else {
            throw "[FALIMENTALE RELEASE] Eseguibile llama-server non trovato per la variante $($v.id) in: $exePath. Per creare un pacchetto di rilascio distribuibile occorre fornire i binari compilati reali o non passare -AllowPlaceholders."
        }
    }

    # Verifica formale PE Binary
    if (-not (Test-IsPEExecutable $exePath)) {
        if (-not $AllowPlaceholders) {
            throw "[FALLIMENTO PE VALIDATION] File non valido o non eseguibile Windows PE (Header MZ mancante): $exePath"
        }
    }
}

# Calcolo Hash SHA-256 e metadata dei file per il manifest canonico
$manifestVariants = @()

foreach ($v in $variants) {
    $fileEntries = @()
    $files = Get-ChildItem -Path $v.dir -Recurse -File

    foreach ($f in $files) {
        $hash = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash.ToLower()
        $relPath = $f.FullName.Substring($targetRuntimeRoot.Length + 1).Replace("\", "/")
        $fileEntries += @{
            path = $relPath
            sizeBytes = $f.Length
            sha256 = $hash
        }
    }

    $manifestVariants += @{
        id = $v.id
        acceleration = $v.accel
        architecture = $v.arch
        requiredCpuFeatures = $v.cpuFeatures
        requiredBackendCapabilities = $v.backendCaps
        executable = $v.exec
        workingDirectory = $v.workDir
        vendorDirectories = $v.vendorDirs
        files = $fileEntries
    }
}

$manifestObject = [ordered]@{
    schemaVersion = 1
    runtimeSetId = "aura-runtime-v$Version"
    llamaCppVersion = $llamaCppVersion
    sourceCommit = $SourceCommit
    variants = $manifestVariants
}

$jsonOutput = $manifestObject | ConvertTo-Json -Depth 10
$manifestFile = "$targetRuntimeRoot\runtime-manifest.json"
Set-Content -Path $manifestFile -Value $jsonOutput -Encoding UTF8

Write-Host "✅ Staging Runtime Multi-Variante e Manifest generati in: $targetRuntimeRoot" -ForegroundColor Green
