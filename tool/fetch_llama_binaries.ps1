# Script di download e sincronizzazione automatica dei binari pre-compilati ufficiali di llama.cpp per A.U.R.A.
param(
    [string]$Tag = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$projectRoot = Resolve-Path "$PSScriptRoot\.."
$lockfilePath = "$projectRoot\tool\runtime\llama-runtime-lock.json"

if (-not (Test-Path $lockfilePath)) {
    throw "[FAIL-CLOSED] Lockfile runtime non trovato: $lockfilePath"
}

$lockJson = Get-Content -Path $lockfilePath -Raw | ConvertFrom-Json
$targetTag = if ([string]::IsNullOrWhiteSpace($Tag)) { $lockJson.llamaCppTag } else { $Tag }
$llamaCppCommit = $lockJson.llamaCppCommit

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " A.U.R.A. Llama.cpp Official Binary Downloader & Sync" -ForegroundColor Cyan
Write-Host " Tag Target: $targetTag | Commit Target: $llamaCppCommit" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

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
if ($targetTag -eq "latest") {
    $apiUrl = "$repoUrl/latest"
} else {
    $apiUrl = "$repoUrl/tags/$targetTag"
}

Write-Host "Interrogazione metadati release da GitHub ($apiUrl)..." -ForegroundColor Yellow

$headers = @{
    "User-Agent" = "AURA-Binary-Fetcher"
}

try {
    $releaseInfo = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get
} catch {
    Write-Host "Tag $targetTag non trovato via API API direct tag, tentativo con /latest..." -ForegroundColor Yellow
    try {
        $apiUrl = "$repoUrl/latest"
        $releaseInfo = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get
    } catch {
        throw "[FAIL-CLOSED] Impossibile recuperare informazioni sulla release llama.cpp: $_"
    }
}

$effectiveTag = $releaseInfo.tag_name

$acquiredMetadata = @()

foreach ($variantLock in $lockJson.variants) {
    $variantId = $variantLock.id
    $destDir = "$projectRoot\$($variantLock.destDir.Replace('/', '\'))"
    $vendorDir = if ($variantLock.vendorDir) { "$projectRoot\$($variantLock.vendorDir.Replace('/', '\'))" } else { "" }
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
        
        # 1. Ricerca assetName esatto dal lockfile
        if ($variantLock.assetName) {
            $selectedAsset = $releaseInfo.assets | Where-Object { $_.name -eq $variantLock.assetName } | Select-Object -First 1
        }

        # 2. Fallback su patterns se assetName non corrisponde
        if (-not $selectedAsset -and $variantLock.patterns) {
            foreach ($pat in $variantLock.patterns) {
                if (-not $selectedAsset) {
                    $selectedAsset = $releaseInfo.assets | Where-Object { $_.name -like $pat } | Select-Object -First 1
                }
            }
        }

        if ($selectedAsset) {
            $downloadUrl = $selectedAsset.browser_download_url
            $zipFileName = $selectedAsset.name
            $zipFilePath = "$tempDownloadDir\$zipFileName"

            Write-Host "Download asset $zipFileName..." -ForegroundColor Yellow
            Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFilePath -Headers $headers

            # Calcolo e verifica SHA-256
            $zipHash = (Get-FileHash -Path $zipFilePath -Algorithm SHA256).Hash.ToLower()
            $zipSize = (Get-Item $zipFilePath).Length
            Write-Host "  Archivio scaricato $zipFileName (SHA-256: $zipHash, Size: $zipSize bytes)" -ForegroundColor Gray

            if ($variantLock.sha256 -and $variantLock.sha256.Trim() -ne "") {
                $expectedHash = $variantLock.sha256.Trim().ToLower()
                if ($zipHash -ne $expectedHash) {
                    throw "[FAIL-CLOSED] Checksum mismatch su asset $zipFileName! Atteso lockfile: $expectedHash, Calcolato: $zipHash"
                }
                Write-Host "  ✅ Checksum lockfile verificato con successo per $zipFileName" -ForegroundColor Green
            }

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
