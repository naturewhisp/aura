$ErrorActionPreference = 'Stop'

Write-Host "==================================================" -ForegroundColor Cyan
Write-Host "A.U.R.A. Standard CI Verification Suite" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan

$rootDir = Get-Location

# Phase 1: Dart Formatting Check
Write-Host "`n[1/5] Running Dart Formatting Check..." -ForegroundColor Yellow
dart format --output=none --set-exit-if-changed .
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Formatting check failed!" -ForegroundColor Red
    exit $LASTEXITCODE
}
Write-Host "[OK] Formatting check passed." -ForegroundColor Green

# Phase 2: Core Static Analysis
Write-Host "`n[2/5] Running Core Static Analysis (dart analyze)..." -ForegroundColor Yellow
dart analyze
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Core static analysis failed!" -ForegroundColor Red
    exit $LASTEXITCODE
}
Write-Host "[OK] Core static analysis passed." -ForegroundColor Green

# Phase 3: Core Offline Test Suite
Write-Host "`n[3/5] Running Core Test Suite (dart test)..." -ForegroundColor Yellow
dart test
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Core test suite failed!" -ForegroundColor Red
    exit $LASTEXITCODE
}
Write-Host "[OK] Core test suite passed." -ForegroundColor Green

# Phase 4: Flutter App Static Analysis
Write-Host "`n[4/5] Running Flutter App Static Analysis (flutter analyze)..." -ForegroundColor Yellow
Set-Location "$rootDir\app"
flutter analyze
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Flutter app static analysis failed!" -ForegroundColor Red
    Set-Location $rootDir
    exit $LASTEXITCODE
}
Write-Host "[OK] Flutter app static analysis passed." -ForegroundColor Green

# Phase 5: Flutter App Test Suite
Write-Host "`n[5/5] Running Flutter App Test Suite (flutter test)..." -ForegroundColor Yellow
flutter test
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Flutter app test suite failed!" -ForegroundColor Red
    Set-Location $rootDir
    exit $LASTEXITCODE
}
Write-Host "[OK] Flutter app test suite passed." -ForegroundColor Green

Set-Location $rootDir
Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "ALL CI CHECKS PASSED SUCCESSFULLY!" -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor Cyan
exit 0
