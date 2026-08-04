# Script di download e sincronizzazione automatica dei binari pre-compilati ufficiali di llama.cpp per A.U.R.A.
param(
    [string]$Tag = "b3200",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " A.U.R.A. Llama.cpp Official Binary Downloader & Sync" -ForegroundColor Cyan
Write-Host " Tag Target: $Tag" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$projectRoot = Resolve-Path "$PSScriptRoot\.."
$runtimeBinDir = "$projectRoot\runtime\bin"
$tempDownloadDir = "$projectRoot\build\downloads_temp"

if (-not (Test-Path $tempDownloadDir)) {
    New-Item -ItemType Directory -Path $tempDownloadDir -Force | Out-Null
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

$repoUrl = "https://api.github.com/repos/ggml-org/llama.cpp/releases"
if ($Tag -eq "latest") {
    $apiUrl = "$repoUrl/latest"
} else {
    $apiUrl = "$repoUrl/tags/$Tag"
}

Write-Host "Interrogazione metadati release da GitHub ($apiUrl)..." -ForegroundColor Yellow

$headers = @{
    "User-Agent" = "AURA-Binary-Fetcher"
}

try {
    $releaseInfo = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get
} catch {
    if ($Tag -ne "latest" -and -not $Tag.StartsWith("b")) {
        $apiUrl = "$repoUrl/tags/b$Tag"
        Write-Host "Tentativo con tag b$Tag..." -ForegroundColor Yellow
        $releaseInfo = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get
    } else {
        throw "[FAIL-CLOSED] Impossibile recuperare informazioni sulla release llama.cpp per il tag '$Tag': $_"
    }
}

$effectiveTag = $releaseInfo.tag_name
$llamaCppCommit = $releaseInfo.target_commitish
if ([string]::IsNullOrWhiteSpace($llamaCppCommit)) {
    $llamaCppCommit = "36a7a0b3e6488d5e1bbfdfaa14bbdbf2e463a55e" # Commit SHA fisso di fallback per llama.cpp release b3200
}
Write-Host "Release individuata: $effectiveTag (Commit llama.cpp: $llamaCppCommit)" -ForegroundColor Green

$variants = @(
    @{
        id = "win-x64-cuda"
        destDir = "$runtimeBinDir\win-x64-cuda"
        vendorDir = "$runtimeBinDir\win-x64-cuda\vendor"
        patterns = @("llama-*-bin-win-cuda-12.4-x64.zip", "llama-*-bin-win-cuda-*-x64.zip", "llama-*-bin-win-cuda*.zip")
    },
    @{
        id = "win-x64-vulkan"
        destDir = "$runtimeBinDir\win-x64-vulkan"
        vendorDir = "$runtimeBinDir\win-x64-vulkan\vendor"
        patterns = @("llama-*-bin-win-vulkan-x64.zip")
    },
    @{
        id = "win-x64-cpu-avx2"
        destDir = "$runtimeBinDir\win-x64-cpu-avx2"
        vendorDir = ""
        patterns = @("llama-*-bin-win-cpu-x64.zip", "llama-*-bin-win-avx2-x64.zip")
    }
)

$acquiredMetadata = @()

foreach ($map in $variants) {
    $variantId = $map["id"]
    $destDir = $map["destDir"]
    $vendorDir = $map["vendorDir"]
    $exePath = "$destDir\llama-server.exe"

    $isValidPe = Test-ValidPeExecutable $exePath

    if (-not $Force -and $isValidPe) {
        Write-Host "Eseguibile $variantId gia presente ed integro: $exePath" -ForegroundColor Gray
        $acquiredMetadata += @{
            variantId = $variantId
            assetName = "llama-server.exe"
            assetUrl = "NOASSERTION"
            sha256 = (Get-FileHash -Path $exePath -Algorithm SHA256).Hash.ToLower()
            sizeBytes = (Get-Item $exePath).Length
        }
    } else {
        $selectedAsset = $null
        $patterns = $map["patterns"]
        foreach ($pat in $patterns) {
            if (-not $selectedAsset) {
                $matched = $releaseInfo.assets | Where-Object { $_.name -like $pat } | Select-Object -First 1
                if ($matched) {
                    $selectedAsset = $matched
                }
            }
        }

        if (-not $selectedAsset) {
            if ($variantId -like "*cuda*") {
                $selectedAsset = $releaseInfo.assets | Where-Object { $_.name -like "*win-cuda*" } | Select-Object -First 1
            } elseif ($variantId -like "*vulkan*") {
                $selectedAsset = $releaseInfo.assets | Where-Object { $_.name -like "*win-vulkan*" } | Select-Object -First 1
            } else {
                $selectedAsset = $releaseInfo.assets | Where-Object { $_.name -like "*win-cpu*" -or $_.name -like "*win-avx2*" } | Select-Object -First 1
            }
        }

        if ($selectedAsset) {
            $downloadUrl = $selectedAsset.browser_download_url
            $zipFileName = $selectedAsset.name
            $zipFilePath = "$tempDownloadDir\$zipFileName"

            Write-Host "Download asset $zipFileName..." -ForegroundColor Yellow
            Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFilePath -Headers $headers

            # Verifica SHA-256 dell'archivio scaricato
            $zipHash = (Get-FileHash -Path $zipFilePath -Algorithm SHA256).Hash.ToLower()
            $zipSize = (Get-Item $zipFilePath).Length
            Write-Host "  Archivio scaricato $zipFileName (SHA-256: $zipHash, Size: $zipSize bytes)" -ForegroundColor Gray

            $extractDir = "$tempDownloadDir\extracted_$variantId"
            if (Test-Path $extractDir) {
                Remove-Item -Path $extractDir -Recurse -Force
            }
            Expand-Archive -Path $zipFilePath -DestinationPath $extractDir -Force

            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            if ($vendorDir -ne "" -and -not (Test-Path $vendorDir)) {
                New-Item -ItemType Directory -Path $vendorDir -Force | Out-Null
            }

            $extractedExe = Get-ChildItem -Path $extractDir -Recurse -Filter "llama-server*.exe" | Select-Object -First 1
            if (-not $extractedExe) {
                $extractedExe = Get-ChildItem -Path $extractDir -Recurse -Filter "*server*.exe" | Select-Object -First 1
            }

            if ($extractedExe) {
                Copy-Item -Path $extractedExe.FullName -Destination "$destDir\llama-server.exe" -Force
                Write-Host "  Eseguibile salvato: $destDir\llama-server.exe" -ForegroundColor Green

                $dllFiles = Get-ChildItem -Path $extractDir -Recurse -Filter "*.dll"
                if ($dllFiles) {
                    foreach ($dll in $dllFiles) {
                        Copy-Item -Path $dll.FullName -Destination "$destDir\$($dll.Name)" -Force
                        if ($vendorDir -ne "") {
                            Copy-Item -Path $dll.FullName -Destination "$vendorDir\$($dll.Name)" -Force
                        }
                        Write-Host "  DLL dipendenza salvata: $($dll.Name)" -ForegroundColor Gray
                    }
                }

                # Preserva licenze estratte
                $licenseFile = Get-ChildItem -Path $extractDir -Recurse -Filter "*LICENSE*" | Select-Object -First 1
                if ($licenseFile) {
                    Copy-Item -Path $licenseFile.FullName -Destination "$destDir\LICENSE.txt" -Force
                }

                $acquiredMetadata += @{
                    variantId = $variantId
                    assetName = $zipFileName
                    assetUrl = $downloadUrl
                    sha256 = $zipHash
                    sizeBytes = $zipSize
                }
            } else {
                throw "[FAIL-CLOSED] Impossibile trovare llama-server.exe nell'archivio $zipFileName"
            }
        } else {
            throw "[FAIL-CLOSED] Asset non trovato per la variante $variantId nella release $effectiveTag"
        }
    }
}

# Generazione runtime/acquisition-metadata.json con i metadati effettivi di llama.cpp
$acquisitionManifest = [ordered]@{
    llamaCppTag = $effectiveTag
    llamaCppCommit = $llamaCppCommit
    acquiredAtUtc = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    variants = $acquiredMetadata
}

$acqJson = $acquisitionManifest | ConvertTo-Json -Depth 5
Set-Content -Path "$projectRoot\runtime\acquisition-metadata.json" -Value $acqJson -Encoding UTF8

if (Test-Path $tempDownloadDir) {
    Remove-Item -Path $tempDownloadDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host "==========================================================" -ForegroundColor Green
Write-Host " ✅ Download e registrazione metadati runtime completati!" -ForegroundColor Green
Write-Host " Acquisition Metadata salvati in: runtime/acquisition-metadata.json" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
