[CmdletBinding()]
param(
    [switch]$RequireCuda,
    [string]$RuntimePath = "",
    [string]$ManifestPath = "",
    [string]$ModelPath = "",
    [string]$OutputReport = "",
    [switch]$KeepLogs
)

$ErrorActionPreference = "Stop"

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  A.U.R.A. Native Smoke Test Orchestrator" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# Set environment variables for the Dart test runner
$env:AURA_TEST_RUNTIME_POLICY = "nativeSmoke"

if ($RequireCuda) {
    $env:AURA_TEST_REQUIRE_ACCELERATION = "cuda"
}

if ($RuntimePath) {
    $env:AURA_TEST_RUNTIME_PATH = $RuntimePath
}

if ($ManifestPath) {
    $env:AURA_TEST_MANIFEST_PATH = $ManifestPath
}

if ($ModelPath) {
    $env:AURA_TEST_SMOKE_MODEL_PATH = $ModelPath
}

if ($OutputReport) {
    $env:AURA_TEST_REPORT_PATH = $OutputReport
}

if ($KeepLogs) {
    $env:AURA_TEST_KEEP_LOGS = "1"
}

try {
    Write-Host "Launching Native Smoke Test Runner (tool/tests/native_smoke_runner.dart)..." -ForegroundColor Yellow
    dart run tool/tests/native_smoke_runner.dart
    $runnerExit = $LASTEXITCODE

    if ($runnerExit -eq 0) {
        Write-Host "Native Smoke Test execution PASSED." -ForegroundColor Green
    } else {
        Write-Host "Native Smoke Test execution FAILED with exit code $runnerExit." -ForegroundColor Red
        exit $runnerExit
    }
}
finally {
    Write-Host "Executing post-test stale process cleanup..." -ForegroundColor Gray
    try {
        dart run bin/aura_cli.dart runtime cleanup-stale 2>$null
    }
    catch {
        # Ignore cleanup errors if CLI tool is not available in standalone execution
    }
}
