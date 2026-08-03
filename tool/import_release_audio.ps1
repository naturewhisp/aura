<#
.SYNOPSIS
    Script orchestratore PowerShell per l'importazione e promozione transazionale degli asset audio A.U.R.A.
.DESCRIPTION
    Delega l'inventario, la validazione RIFF/WAVE e la promozione al tool Dart `tool/import_release_audio.dart`.
.EXAMPLE
    .\tool\import_release_audio.ps1 -SourcePath "$env:APPDATA\aura\audio"
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory=$false)]
    [string]$SourcePath = "",

    [Parameter(Mandatory=$false)]
    [string]$DestinationPath = "distribution/audio",

    [Parameter(Mandatory=$false)]
    [string]$AppAssetPath = "app/assets/audio"
)

$ErrorActionPreference = "Stop"

$argsList = @("run", "tool/import_release_audio.dart")
if ($SourcePath -ne "") {
    $argsList += "--source"
    $argsList += $SourcePath
}
if ($DestinationPath -ne "") {
    $argsList += "--destination"
    $argsList += $DestinationPath
}
if ($AppAssetPath -ne "") {
    $argsList += "--app-asset"
    $argsList += $AppAssetPath
}

& dart $argsList
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] L'importazione delle risorse audio e fallita (exit code $LASTEXITCODE)." -ForegroundColor Red
    exit $LASTEXITCODE
}
