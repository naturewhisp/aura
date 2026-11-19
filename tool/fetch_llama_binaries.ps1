# Script di download e sincronizzazione automatica dei binari pre-compilati ufficiali di llama.cpp per A.U.R.A.
# Esegue un'acquisizione rigorosamente hash-pinned e verificata contro tool/runtime/llama-runtime-lock.json.
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
$targetTag = $lockJson.llamaCppTag
$llamaCppCommit = $lockJson.llamaCppCommit

if (-not [string]::IsNullOrWhiteSpace($Tag) -and $Tag -ne $targetTag) {
    throw "[FAIL-CLOSED] Parametro -Tag '$Tag' non corrisponde al tag locked '$targetTag' definito in llama-runtime-lock.json"
}

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " A.U.R.A. Hash-Pinned Llama.cpp Official Binary Sync" -ForegroundColor Cyan
Write-Host " Tag Locked: $targetTag | Commit Locked: $llamaCppCommit" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

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

$apiUrl = "https://api.github.com/repos/ggml-org/llama.cpp/releases/tags/$targetTag"
Write-Host "Interrogazione metadati release da GitHub ($apiUrl)..." -ForegroundColor Yellow

$headers = @{
    "User-Agent" = "AURA-Binary-Fetcher"
}

try {
    $releaseInfo = Invoke-RestMethod -Uri $apiUrl -Headers $headers -Method Get
} catch {
    throw "[FAIL-CLOSED] Impossibile recuperare informazioni sulla release llama.cpp per il tag locked '$targetTag': $_"
}

if ($releaseInfo.tag_name -ne $targetTag) {
    throw "[FAIL-CLOSED] Tag upstream inatteso! Atteso: '$targetTag', Ricevuto: '$($releaseInfo.tag_name)'"
}

# Scarica un asset della release locked e ne verifica dimensione e SHA-256 (fail-closed).
function Get-VerifiedReleaseAsset([string]$assetName, [string]$expectedSha256, [long]$expectedSize) {
    $asset = $releaseInfo.assets | Where-Object { $_.name -eq $assetName } | Select-Object -First 1
    if (-not $asset) {
        throw "[FAIL-CLOSED] Asset locked '$assetName' non trovato nella release upstream $targetTag"
    }
    $zipPath = "$tempDownloadDir\$assetName"
    Write-Host "Download asset $assetName..." -ForegroundColor Yellow
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath -Headers $headers

    $size = (Get-Item $zipPath).Length
    if ($expectedSize -gt 0 -and $size -ne $expectedSize) {
        throw "[FAIL-CLOSED] Dimensione archivio mismatch su ${assetName}! Atteso: $expectedSize bytes, Ricevuto: $size bytes"
    }
    $hash = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToLower()
    if ($hash -ne $expectedSha256.Trim().ToLower()) {
        throw "[FAIL-CLOSED] Checksum mismatch su asset ${assetName}! Atteso lockfile: $expectedSha256, Calcolato: $hash"
    }
    Write-Host "  Size ($size bytes) e Checksum SHA-256 ($hash) verificati." -ForegroundColor Green
    return @{ path = $zipPath; url = $asset.browser_download_url; sha256 = $hash; sizeBytes = $size }
}

$acquiredMetadata = @()

foreach ($variantLock in $lockJson.variants) {
    $variantId = $variantLock.id
    $destDir = "$projectRoot\$($variantLock.destDir.Replace('/', '\'))"
    $vendorDir = if ($variantLock.vendorDir) { "$projectRoot\$($variantLock.vendorDir.Replace('/', '\'))" } else { "" }
    $exePath = "$destDir\llama-server.exe"

    if ([string]::IsNullOrWhiteSpace($variantLock.assetName)) {
        throw "[FAIL-CLOSED] assetName mancante nel lockfile per la variante $variantId"
    }

    if ([string]::IsNullOrWhiteSpace($variantLock.sha256)) {
        throw "[FAIL-CLOSED] SHA-256 mancante nel lockfile per la variante $variantId"
    }

    $expectedHash = $variantLock.sha256.Trim().ToLower()
    $expectedSize = [long]$variantLock.sizeBytes

    $isValidPe = Test-ValidPeExecutable $exePath

    if (-not $Force -and $isValidPe) {
        Write-Host "Eseguibile $variantId gia presente ed integro: $exePath" -ForegroundColor Gray
        $acquiredMetadata += @{
            variantId = $variantId
            assetName = $variantLock.assetName
            assetUrl = "NOASSERTION"
            sha256 = $expectedHash
            sizeBytes = $expectedSize
        }
    } else {
        # Selezione ESATTA dell'asset dal lockfile (senza wildcard o fallback a latest)
        $selectedAsset = $releaseInfo.assets | Where-Object { $_.name -eq $variantLock.assetName } | Select-Object -First 1

        if (-not $selectedAsset) {
            throw "[FAIL-CLOSED] Asset locked '$($variantLock.assetName)' non trovato nella release upstream $targetTag"
        }

        $downloadUrl = $selectedAsset.browser_download_url
        $zipFileName = $selectedAsset.name
        $zipFilePath = "$tempDownloadDir\$zipFileName"

        Write-Host "Download asset $zipFileName..." -ForegroundColor Yellow
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFilePath -Headers $headers

        # Verification 1: Size check
        $zipSize = (Get-Item $zipFilePath).Length
        if ($expectedSize -gt 0 -and $zipSize -ne $expectedSize) {
            throw "[FAIL-CLOSED] Dimensione archivio mismatch su $zipFileName! Atteso: $expectedSize bytes, Ricevuto: $zipSize bytes"
        }

        # Verification 2: SHA-256 Checksum check
        $zipHash = (Get-FileHash -Path $zipFilePath -Algorithm SHA256).Hash.ToLower()
        if ($zipHash -ne $expectedHash) {
            throw "[FAIL-CLOSED] Checksum mismatch su asset $zipFileName! Atteso lockfile: $expectedHash, Calcolato: $zipHash"
        }

        Write-Host "  ✅ Size ($zipSize bytes) e Checksum SHA-256 ($zipHash) verificati con successo!" -ForegroundColor Green

        # Estrazione solo dopo il superamento dei controlli
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
    }

    # Pacchetti vendor ufficiali della stessa release (es. runtime CUDA 12 per la
    # variante cuda): inclusi nel bundle invece di essere prelevati dalla macchina
    # di build (Toolkit o LM Studio), cosi' l'esecuzione GPU non dipende da
    # software di terze parti installato sul PC dell'utente.
    foreach ($vendorAsset in @($variantLock.vendorAssets)) {
        if (-not $vendorAsset) { continue }
        if ($vendorDir -eq "") {
            throw "[FAIL-CLOSED] vendorAssets dichiarati senza vendorDir per la variante $variantId"
        }
        if (-not (Test-Path $vendorDir)) {
            New-Item -ItemType Directory -Path $vendorDir -Force | Out-Null
        }
        $required = @($vendorAsset.requiredFiles)
        $alreadyPresent = ($required.Count -gt 0) -and (@($required | Where-Object { -not (Test-Path "$vendorDir\$_") }).Count -eq 0)

        if (-not $Force -and $alreadyPresent) {
            Write-Host "Pacchetto vendor $($vendorAsset.assetName) gia presente in $vendorDir" -ForegroundColor Gray
            $vendorMeta = @{ sha256 = $vendorAsset.sha256; sizeBytes = [long]$vendorAsset.sizeBytes; url = "NOASSERTION" }
        } else {
            $vendorMeta = Get-VerifiedReleaseAsset $vendorAsset.assetName $vendorAsset.sha256 ([long]$vendorAsset.sizeBytes)
            $vendorExtract = "$tempDownloadDir\vendor_${variantId}_$($vendorAsset.assetName)"
            if (Test-Path $vendorExtract) { Remove-Item -Path $vendorExtract -Recurse -Force }
            Expand-Archive -Path $vendorMeta.path -DestinationPath $vendorExtract -Force
            Get-ChildItem -Path $vendorExtract -Recurse -Filter "*.dll" | ForEach-Object {
                Copy-Item -Path $_.FullName -Destination "$vendorDir\$($_.Name)" -Force
                Write-Host "  DLL vendor salvata: $($_.Name)" -ForegroundColor Gray
            }
            $missing = @($required | Where-Object { -not (Test-Path "$vendorDir\$_") })
            if ($missing.Count -gt 0) {
                throw "[FAIL-CLOSED] Il pacchetto $($vendorAsset.assetName) non contiene: $($missing -join ', ')"
            }
        }

        $acquiredMetadata += @{
            variantId = $variantId
            assetName = $vendorAsset.assetName
            assetUrl = $vendorMeta.url
            sha256 = $vendorMeta.sha256
            sizeBytes = $vendorMeta.sizeBytes
            vendor = $true
        }
    }
}

# Generazione runtime/acquisition-metadata.json con i metadati effettivi di llama.cpp
$acquisitionManifest = [ordered]@{
    llamaCppTag = $targetTag
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
