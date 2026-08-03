<#
.SYNOPSIS
    Script di staging e preparazione locale delle varianti di runtime llama-server (CUDA, Vulkan, CPU AVX2) per A.U.R.A.

.PARAMETER Version
    Versione del pacchetto di rilascio (es. "0.1.0" o "1.0.0").

.PARAMETER SourceCommit
    SHA-1 o tag del commit sorgente per la tracciabilità del manifest.
#>
param(
    [string]$Version = "0.1.0",
    [string]$SourceCommit = ""
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " A.U.R.A. Llama Runtime Staging & Multi-Variant Builder" -ForegroundColor Cyan
Write-Host " Versione: $Version" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$projectRoot = Resolve-Path "$PSScriptRoot\.."
$runtimeRoot = "$projectRoot\runtime"
$binRoot = "$runtimeRoot\bin"

if ([string]::IsNullOrWhiteSpace($SourceCommit)) {
    try {
        $SourceCommit = (git rev-parse HEAD).Trim()
    } catch {
        $SourceCommit = "unknown"
    }
}

# Creazione delle directory per le 3 varianti ufficiali
$variants = @(
    @{
        id = "win-x64-cuda"
        accel = "cuda"
        arch = "x64"
        features = @("avx2", "fma", "cuda12")
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
        features = @("avx2", "vulkan")
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
        features = @("avx2", "fma")
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

# Verifica o creazione di stub binaries di staging se non già forniti esternamente
foreach ($v in $variants) {
    $exePath = "$($v.dir)\llama-server.exe"
    if (-not (Test-Path $exePath)) {
        Write-Host "⚠️ Staging placeholder per $($v.id): $exePath" -ForegroundColor Yellow
        Set-Content -Path $exePath -Value "AURA_LLAMA_SERVER_PLACEHOLDER_STAGING" -Encoding UTF8
    }
}

# Calcolo Hash SHA-256 e metadata dei file
$manifestVariants = @()

foreach ($v in $variants) {
    $fileEntries = @()
    $files = Get-ChildItem -Path $v.dir -Recurse -File

    foreach ($f in $files) {
        $hash = (Get-FileHash -Path $f.FullName -Algorithm SHA256).Hash.ToLower()
        $relPath = $f.FullName.Substring($v.dir.Length + 1).Replace("\", "/")
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
        requiredCpuFeatures = $v.features
        executable = $v.exec
        workingDirectory = $v.workDir
        vendorDirectories = $v.vendorDirs
        files = $fileEntries
    }
}

$manifestObject = [ordered]@{
    schemaVersion = 1
    runtimeSetId = "aura-runtime-v$Version"
    llamaCppVersion = "b3200"
    sourceCommit = $SourceCommit
    variants = $manifestVariants
}

$jsonOutput = $manifestObject | ConvertTo-Json -Depth 10
$manifestFile = "$runtimeRoot\runtime-manifest.json"
Set-Content -Path $manifestFile -Value $jsonOutput -Encoding UTF8

Write-Host "✅ Runtime Multi-Variante e Manifest generati con successo in: $manifestFile" -ForegroundColor Green
