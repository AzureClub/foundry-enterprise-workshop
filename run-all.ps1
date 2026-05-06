<#
.SYNOPSIS
    Master orchestrator — runs full Foundry BYO VNet test suite.
.DESCRIPTION
    Executes all phases in order:
      Phase 0: Pre-flight checks
      Phase 1: Deploy Foundry infrastructure (Bicep)
      Phase 2: Deploy APIM (Bicep)
      Phase 3: Import APIs into APIM
      Phase 4: Run all validation tests
      Phase 5: Generate E2E report

    Use -SkipDeploy to run only tests (if infrastructure already exists).
    Use -SkipApim to skip APIM deployment and tests.
    Use -WhatIf to validate Bicep without deploying.
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "$PSScriptRoot\config\test-config.json",
    [switch]$SkipDeploy,
    [switch]$SkipApim,
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$scriptDir = "$PSScriptRoot\scripts"
$startTime = Get-Date

Write-Host @"

 ╔══════════════════════════════════════════════════════════════╗
 ║   FOUNDRY BYO VNet — FULL TEST SUITE                        ║
 ║   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')                                     ║
 ╚══════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

$phases = @()
$failedPhase = $null

function Run-Phase($number, $name, $script, [string[]]$extraArgs = @()) {
    Write-Host "`n┌──────────────────────────────────────────────────────┐" -ForegroundColor Cyan
    Write-Host "│  PHASE $number: $name" -ForegroundColor Cyan
    Write-Host "└──────────────────────────────────────────────────────┘" -ForegroundColor Cyan

    $phaseStart = Get-Date
    & $script -ConfigPath $ConfigPath @extraArgs
    $exitCode = $LASTEXITCODE
    $duration = (Get-Date) - $phaseStart

    $status = if ($exitCode -eq 0) { "PASS" } else { "FAIL" }
    $icon = if ($exitCode -eq 0) { [char]0x2705 } else { [char]0x274C }
    $script:phases += [PSCustomObject]@{
        Phase = $number
        Name = $name
        Status = $status
        Icon = $icon
        Duration = "{0:mm\:ss}" -f $duration
    }

    if ($exitCode -ne 0) {
        $script:failedPhase = $number
        Write-Host "`n$([char]0x274C) Phase $number FAILED. Stopping." -ForegroundColor Red
        return $false
    }
    Write-Host "`n$([char]0x2705) Phase $number completed ($("{0:mm\:ss}" -f $duration))" -ForegroundColor Green
    return $true
}

# ============================================================================
# Phase 0: Pre-flight
# ============================================================================
if (-not (Run-Phase 0 "PRE-FLIGHT CHECKS" "$scriptDir\00-preflight.ps1")) {
    Write-Host "Fix pre-flight issues before continuing." -ForegroundColor Red
    exit 1
}

# ============================================================================
# Phase 1: Deploy Foundry
# ============================================================================
if (-not $SkipDeploy) {
    $deployArgs = @()
    if ($WhatIf) { $deployArgs += "-WhatIf" }

    if (-not (Run-Phase 1 "DEPLOY FOUNDRY INFRASTRUCTURE" "$scriptDir\01-deploy-foundry.ps1" $deployArgs)) {
        exit 1
    }

    if ($WhatIf) {
        Write-Host "`nWhatIf mode — skipping remaining phases." -ForegroundColor Yellow
        exit 0
    }
} else {
    Write-Host "`n⏭️  Phase 1: SKIPPED (--SkipDeploy)" -ForegroundColor Yellow
    $phases += [PSCustomObject]@{ Phase=1; Name="DEPLOY FOUNDRY"; Status="SKIP"; Icon="⏭️"; Duration="--" }
}

# ============================================================================
# Phase 2: Deploy APIM
# ============================================================================
if (-not $SkipDeploy -and -not $SkipApim) {
    if (-not (Run-Phase 2 "DEPLOY APIM (INTERNAL VNet)" "$scriptDir\02-deploy-apim.ps1")) {
        Write-Host "APIM deployment failed. Continuing with Foundry-only tests..." -ForegroundColor Yellow
    }
} else {
    $skipReason = if ($SkipApim) { "--SkipApim" } else { "--SkipDeploy" }
    Write-Host "`n⏭️  Phase 2: SKIPPED ($skipReason)" -ForegroundColor Yellow
    $phases += [PSCustomObject]@{ Phase=2; Name="DEPLOY APIM"; Status="SKIP"; Icon="⏭️"; Duration="--" }
}

# ============================================================================
# Phase 3: Import APIs
# ============================================================================
if (-not $SkipApim) {
    $apimExists = az apim list --resource-group (Get-Content $ConfigPath -Raw | ConvertFrom-Json).resource_group --query "[0].name" -o tsv 2>$null
    if ($apimExists) {
        if (-not (Run-Phase 3 "IMPORT OpenAI + MCP APIs" "$scriptDir\03-import-openapi-mcp.ps1")) {
            Write-Host "API import failed. Continuing with tests..." -ForegroundColor Yellow
        }
    } else {
        Write-Host "`n⏭️  Phase 3: SKIPPED (APIM not deployed)" -ForegroundColor Yellow
        $phases += [PSCustomObject]@{ Phase=3; Name="IMPORT APIs"; Status="SKIP"; Icon="⏭️"; Duration="--" }
    }
} else {
    Write-Host "`n⏭️  Phase 3: SKIPPED (--SkipApim)" -ForegroundColor Yellow
    $phases += [PSCustomObject]@{ Phase=3; Name="IMPORT APIs"; Status="SKIP"; Icon="⏭️"; Duration="--" }
}

# ============================================================================
# Phase 4: Validation Tests
# ============================================================================
Write-Host "`n┌──────────────────────────────────────────────────────┐" -ForegroundColor Cyan
Write-Host "│  PHASE 4: VALIDATION TESTS                           │" -ForegroundColor Cyan
Write-Host "└──────────────────────────────────────────────────────┘" -ForegroundColor Cyan

$testScripts = @(
    @{ Name = "Network";   Script = "04-test-network.ps1" }
    @{ Name = "PE";        Script = "05-test-pe.ps1" }
    @{ Name = "Agent";     Script = "06-test-agent.ps1" }
    @{ Name = "Identity";  Script = "08-test-identity.ps1" }
    @{ Name = "Portal";    Script = "10-test-portal-access.ps1" }
)

if (-not $SkipApim) {
    $testScripts += @{ Name = "APIM"; Script = "07-test-apim.ps1" }
}

$testResults = @()
foreach ($test in $testScripts) {
    Write-Host "`n--- Test: $($test.Name) ---" -ForegroundColor Yellow
    $testStart = Get-Date
    & "$scriptDir\$($test.Script)" -ConfigPath $ConfigPath
    $testExit = $LASTEXITCODE
    $testDuration = (Get-Date) - $testStart

    $testResults += [PSCustomObject]@{
        Name = $test.Name
        Status = if ($testExit -eq 0) { "PASS" } else { "FAIL" }
        Icon = if ($testExit -eq 0) { [char]0x2705 } else { [char]0x274C }
        Duration = "{0:mm\:ss}" -f $testDuration
    }
}

$testPass = ($testResults | Where-Object { $_.Status -eq "PASS" }).Count
$testFail = ($testResults | Where-Object { $_.Status -eq "FAIL" }).Count
$phases += [PSCustomObject]@{
    Phase = 4
    Name = "VALIDATION ($testPass pass, $testFail fail)"
    Status = if ($testFail -eq 0) { "PASS" } else { "FAIL" }
    Icon = if ($testFail -eq 0) { [char]0x2705 } else { [char]0x274C }
    Duration = "{0:mm\:ss}" -f (($testResults | ForEach-Object { [TimeSpan]::ParseExact($_.Duration, "mm\:ss", $null) } | Measure-Object -Property TotalSeconds -Sum).Sum | ForEach-Object { [TimeSpan]::FromSeconds($_) })
}

# ============================================================================
# Phase 5: E2E Report
# ============================================================================
Run-Phase 5 "E2E REPORT" "$scriptDir\09-e2e-report.ps1" | Out-Null

# ============================================================================
# Final Summary
# ============================================================================
$totalDuration = (Get-Date) - $startTime

Write-Host @"

 ╔══════════════════════════════════════════════════════════════╗
 ║   EXECUTION SUMMARY                                         ║
 ╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

foreach ($p in $phases) {
    $color = switch ($p.Status) { "PASS" { "Green" } "FAIL" { "Red" } "SKIP" { "Yellow" } }
    Write-Host "  $($p.Icon) Phase $($p.Phase): $($p.Name)  [$($p.Duration)]" -ForegroundColor $color
}

Write-Host "`n  Test Details:" -ForegroundColor Cyan
foreach ($t in $testResults) {
    $color = if ($t.Status -eq "PASS") { "Green" } else { "Red" }
    Write-Host "    $($t.Icon) $($t.Name) [$($t.Duration)]" -ForegroundColor $color
}

Write-Host "`n  Total time: $("{0:hh\:mm\:ss}" -f $totalDuration)" -ForegroundColor Cyan

if ($testFail -gt 0 -or $failedPhase) {
    Write-Host "`n  $([char]0x274C) VERDICT: NO-GO ($testFail test(s) failed)" -ForegroundColor Red
    exit 1
} else {
    Write-Host "`n  $([char]0x2705) VERDICT: GO (all tests passed)" -ForegroundColor Green
    exit 0
}
