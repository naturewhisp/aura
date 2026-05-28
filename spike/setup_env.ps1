# Ensure we are in the script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($ScriptDir) { Set-Location $ScriptDir }

Write-Host "Creating Python virtual environment in .venv..." -ForegroundColor Green
python -m venv ..\.venv

Write-Host "Activating virtual environment..." -ForegroundColor Green
& ..\.venv\Scripts\Activate.ps1

Write-Host "Upgrading pip..." -ForegroundColor Green
python -m pip install --upgrade pip

Write-Host "Installing dependencies..." -ForegroundColor Green
python -m pip install openai jinja2 psutil gputil httpx

Write-Host "Environment setup complete!" -ForegroundColor Green
