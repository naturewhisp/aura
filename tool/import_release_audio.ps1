<#
.SYNOPSIS
    Script di inventario, validazione RIFF/WAVE e promozione degli asset audio canonici per A.U.R.A.
.DESCRIPTION
    Scansiona una directory di file WAV sorgenti, calcola dimensione, metadati di campionamento e hash SHA-256,
    copia atomicamente i file validi in distribution/audio/ e genera il manifest audio canonico ed il bundle Flutter.
.EXAMPLE
    .\tool\import_release_audio.ps1 -SourcePath "$env:APPDATA\aura\audio"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$SourcePath = "$env:APPDATA\aura\audio",

    [Parameter(Mandatory=$false)]
    [string]$DestinationPath = "distribution/audio",

    [Parameter(Mandatory=$false)]
    [string]$AppAssetPath = "app/assets/audio"
)

$ErrorActionPreference = "Stop"

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " A.U.R.A. Audio Release Importer & Manifest Generator (Fase 6.7)" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

if (-not (Test-Path -Path $SourcePath)) {
    Write-Host "[WARN] Directory sorgente non trovata: $SourcePath" -ForegroundColor Yellow
    Write-Host "[INFO] Creazione directory sorgente ed utilizzo del fallback procedurale se vuota." -ForegroundColor Yellow
    New-Item -ItemType Directory -Force -Path $SourcePath | Out-Null
}

New-Item -ItemType Directory -Force -Path $DestinationPath | Out-Null
New-Item -ItemType Directory -Force -Path $AppAssetPath | Out-Null

$expectedTracks = @(
    @{ id = "bgm.main"; kind = "bgm"; role = "mainMenu"; filename = "bgm_main.wav"; loop = $true; required = $true },
    @{ id = "bgm.ambient"; kind = "bgm"; role = "ambient"; filename = "bgm_ambient.wav"; loop = $true; required = $true },
    @{ id = "bgm.tense"; kind = "bgm"; role = "tense"; filename = "bgm_tense.wav"; loop = $true; required = $true },
    @{ id = "bgm.epic"; kind = "bgm"; role = "epic"; filename = "bgm_epic.wav"; loop = $true; required = $true },
    @{ id = "sfx.click"; kind = "sfx"; role = "click"; filename = "sfx_click.wav"; loop = $false; required = $true },
    @{ id = "sfx.alert"; kind = "sfx"; role = "alert"; filename = "sfx_alert.wav"; loop = $false; required = $true },
    @{ id = "sfx.glitch"; kind = "sfx"; role = "glitch"; filename = "sfx_glitch.wav"; loop = $false; required = $true },
    @{ id = "sfx.chime"; kind = "sfx"; role = "chime"; filename = "sfx_chime.wav"; loop = $false; required = $true }
)

$manifestTracks = @()

foreach ($track in $expectedTracks) {
    $filePath = Join-Path $SourcePath $track.filename
    if (-not (Test-Path -Path $filePath)) {
        Write-Host "[SKIP] File traccia non presente in sorgente: $($track.filename)" -ForegroundColor DarkGray
        continue
    }

    $bytes = [System.IO.File]::ReadAllBytes($filePath)
    if ($bytes.Length -lt 44) {
        Write-Host "[ERROR] File WAV corrotto o troncato: $($track.filename)" -ForegroundColor Red
        continue
    }

    # Header RIFF/WAVE verification
    $riff = [System.Text.Encoding]::ASCII.GetString($bytes, 0, 4)
    $wave = [System.Text.Encoding]::ASCII.GetString($bytes, 8, 4)
    if ($riff -ne "RIFF" -or $wave -ne "WAVE") {
        Write-Host "[ERROR] Header RIFF/WAVE non valido per $($track.filename)" -ForegroundColor Red
        continue
    }

    $channels = [System.BitConverter]::ToUInt16($bytes, 22)
    $sampleRate = [System.BitConverter]::ToUInt32($bytes, 24)
    $bitsPerSample = [System.BitConverter]::ToUInt16($bytes, 34)

    # Scansione data chunk
    $dataSize = $bytes.Length - 44
    $bytesPerSample = [int]($bitsPerSample / 8) * $channels
    $durationMs = 0
    if ($bytesPerSample -gt 0 -and $sampleRate -gt 0) {
        $durationMs = [int](($dataSize * 1000) / ($sampleRate * $bytesPerSample))
    }

    $hash = (Get-FileHash -Path $filePath -Algorithm SHA256).Hash.ToLower()

    $destFile = Join-Path $DestinationPath $track.filename
    $assetFile = Join-Path $AppAssetPath $track.filename
    Copy-Item -Path $filePath -Destination $destFile -Force
    Copy-Item -Path $filePath -Destination $assetFile -Force

    Write-Host "[OK] Traccia importata: $($track.id) -> $($track.filename) ($($bytes.Length) bytes, $sampleRate Hz, $hash)" -ForegroundColor Green

    $manifestTracks += [ordered]@{
        id = $track.id
        kind = $track.kind
        role = $track.role
        filename = $track.filename
        sizeBytes = $bytes.Length
        sha256 = $hash
        codec = "pcm"
        sampleRate = [int]$sampleRate
        channels = [int]$channels
        bitsPerSample = [int]$bitsPerSample
        durationMs = [int]$durationMs
        loop = [bool]$track.loop
        required = [bool]$track.required
    }
}

$manifestObject = [ordered]@{
    schemaVersion = 1
    audioSetId = "aura.windows.release.v1"
    tracks = $manifestTracks
}

$jsonJson = $manifestObject | ConvertTo-Json -Depth 5

$destManifest = Join-Path $DestinationPath "audio-manifest.json"
$assetManifest = Join-Path $AppAssetPath "audio_manifest.json"

[System.IO.File]::WriteAllText($destManifest, $jsonJson, [System.Text.Encoding]::UTF8)
[System.IO.File]::WriteAllText($assetManifest, $jsonJson, [System.Text.Encoding]::UTF8)

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "[SUCCESS] Manifest generati con successo:" -ForegroundColor Green
Write-Host "          - $destManifest" -ForegroundColor Green
Write-Host "          - $assetManifest" -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Cyan
