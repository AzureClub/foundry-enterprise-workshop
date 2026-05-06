<#
.SYNOPSIS
    Deploy Foundry BYO VNet infrastructure via Bicep.
.DESCRIPTION
    Deploys main.bicep template with all Foundry resources, BYO VNet, PE, DNS, RBAC, Bastion, VPN.
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "$PSScriptRoot\..\config\test-config.json",
    [Parameter(Mandatory=$false)]
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rg = $config.resource_group
$location = $config.location
$bicepDir = "$PSScriptRoot\..\bicep"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  FAZA 1: DEPLOY FOUNDRY BYO VNet" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Validate VM password
if (-not $env:VM_ADMIN_PASSWORD) {
    Write-Host "ERROR: Set VM_ADMIN_PASSWORD env variable before deploying." -ForegroundColor Red
    Write-Host '  $env:VM_ADMIN_PASSWORD = "YourSecurePassword123!"' -ForegroundColor Yellow
    exit 1
}

# Ensure RG exists
Write-Host "Ensuring resource group $rg in $location..." -ForegroundColor Yellow
az group create --name $rg --location $location -o none 2>&1

$deployCmd = @(
    "az", "deployment", "group", "create",
    "--resource-group", $rg,
    "--template-file", "$bicepDir\main.bicep",
    "--parameters", "$bicepDir\main.bicepparam",
    "--name", "foundry-byovnet-$(Get-Date -Format 'yyyyMMdd-HHmmss')",
    "--verbose"
)

if ($WhatIf) {
    $deployCmd = @(
        "az", "deployment", "group", "validate",
        "--resource-group", $rg,
        "--template-file", "$bicepDir\main.bicep",
        "--parameters", "$bicepDir\main.bicepparam"
    )
    Write-Host "Running WHAT-IF validation only..." -ForegroundColor Yellow
}

Write-Host "Deploying Bicep template..." -ForegroundColor Yellow
Write-Host "  Template: $bicepDir\main.bicep" -ForegroundColor Gray
Write-Host "  RG: $rg | Region: $location" -ForegroundColor Gray
Write-Host "  This may take 15-30 minutes (VPN Gateway takes ~25 min)..." -ForegroundColor Gray
Write-Host ""

$result = & $deployCmd[0] $deployCmd[1..($deployCmd.Length-1)] 2>&1
$exitCode = $LASTEXITCODE

# Retry logic for AccountProvisioningStateInvalid (networkInjections async provisioning)
$maxRetries = 2
$retryCount = 0
while ($exitCode -ne 0 -and $retryCount -lt $maxRetries) {
    $resultText = $result -join "`n"
    if ($resultText -match "AccountProvisioningStateInvalid|Account .+ in state Accepted") {
        $retryCount++
        Write-Host "`n⚠️  Account still provisioning (networkInjections). Waiting for Succeeded state..." -ForegroundColor Yellow
        $accountName = $config.foundry.account_name
        $waitSeconds = 0
        $maxWait = 300
        do {
            Start-Sleep -Seconds 15
            $waitSeconds += 15
            $state = az cognitiveservices account show --name $accountName --resource-group $rg --query "properties.provisioningState" -o tsv 2>&1
            Write-Host "  [$waitSeconds`s] Account state: $state" -ForegroundColor Gray
        } while ($state -ne "Succeeded" -and $waitSeconds -lt $maxWait)
        
        if ($state -eq "Succeeded") {
            Write-Host "`n🔄 Account ready. Retrying deployment ($retryCount/$maxRetries)..." -ForegroundColor Yellow
            $deployCmd[11] = "foundry-byovnet-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
            $result = & $deployCmd[0] $deployCmd[1..($deployCmd.Length-1)] 2>&1
            $exitCode = $LASTEXITCODE
        } else {
            Write-Host "❌ Account did not reach Succeeded state after ${maxWait}s" -ForegroundColor Red
            break
        }
    } else {
        break
    }
}

if ($exitCode -eq 0) {
    Write-Host "`n$([char]0x2705) Deployment SUCCEEDED" -ForegroundColor Green
    
    # Show key outputs
    Write-Host "`n--- Deployment Outputs ---" -ForegroundColor Cyan
    az deployment group show --resource-group $rg --name (az deployment group list --resource-group $rg --query "[0].name" -o tsv) --query "properties.outputs" -o json 2>&1
} else {
    Write-Host "`n$([char]0x274C) Deployment FAILED" -ForegroundColor Red
    Write-Host $result -ForegroundColor Red
    exit 1
}
