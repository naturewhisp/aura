[CmdletBinding()]
param(
    [switch]$RequireInstalled = $true,
    [string]$ActorModelPath = "",
    [string]$EvaluatorModelPath = "",
    [string]$RuntimePath = "",
    [switch]$RequireCuda,
    [string]$OutputReport = "",
    [switch]$KeepLogs
)

$ErrorActionPreference = "Stop"

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  A.U.R.A. Real-Model Integration Orchestrator" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan

# Set environment variables for the Dart test runner
$env:AURA_TEST_RUNTIME_POLICY = "requireInstalledModels"

if ($RequireCuda) {
    $env:AURA_TEST_REQUIRE_ACCELERATION = "cuda"
}

if ($RuntimePath) {
    $env:AURA_TEST_RUNTIME_PATH = $RuntimePath
}

if ($ActorModelPath) {
    $env:AURA_TEST_ACTOR_MODEL_PATH = $ActorModelPath
}

if ($EvaluatorModelPath) {
    $env:AURA_TEST_EVALUATOR_MODEL_PATH = $EvaluatorModelPath
}

if ($OutputReport) {
    $env:AURA_TEST_REPORT_PATH = $OutputReport
}

if ($KeepLogs) {
    $env:AURA_TEST_KEEP_LOGS = "1"
}

try {
    Write-Host "Launching Real-Model Integration Runner (tool/tests/real_model_runner.dart)..." -ForegroundColor Yellow
    dart run tool/tests/real_model_runner.dart
    $runnerExit = $LASTEXITCODE

    if ($runnerExit -eq 0) {
        Write-Host "Real-Model Integration Test execution PASSED." -ForegroundColor Green
    } else {
        Write-Host "Real-Model Integration Test execution FAILED with exit code $runnerExit." -ForegroundColor Red
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
