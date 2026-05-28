Write-Host "Installing official Dart SDK (Google.DartSDK) using winget..." -ForegroundColor Green
winget install -e --id Google.DartSDK --accept-source-agreements --accept-package-agreements

Write-Host "Installation completed! Checking if dart is in PATH..." -ForegroundColor Green
# Refresh environment path for this session
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
where.exe dart
