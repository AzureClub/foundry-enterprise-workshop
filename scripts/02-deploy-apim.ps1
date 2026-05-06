<#
.SYNOPSIS
    Deploy APIM Developer (Internal VNet) via Bicep.
.DESCRIPTION
    Deploys apim.bicep — adds APIM subnet, NSG, APIM instance, DNS, RBAC.
    Requires main.bicep to be deployed first (existing VNet + Foundry Account).
    APIM Developer deployment takes 30-45 minutes.
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
Write-Host "  DEPLOY APIM (Internal VNet)" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# Verify Foundry resources exist
Write-Host "Verifying Foundry infrastructure exists..." -ForegroundColor Yellow
$vnetCheck = az network vnet show --name $config.vnet.name --resource-group $rg -o json 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: VNet not found. Deploy main.bicep first (01-deploy-foundry.ps1)." -ForegroundColor Red
    exit 1
}
Write-Host "  VNet: $($config.vnet.name) found" -ForegroundColor Green

$aiCheck = az cognitiveservices account list --resource-group $rg --query "[0].name" -o tsv 2>&1
if ($LASTEXITCODE -ne 0 -or -not $aiCheck) {
    Write-Host "ERROR: Foundry Account not found. Deploy main.bicep first." -ForegroundColor Red
    exit 1
}
Write-Host "  Foundry Account: $aiCheck found" -ForegroundColor Green

$deployCmd = @(
    "az", "deployment", "group", "create",
    "--resource-group", $rg,
    "--template-file", "$bicepDir\apim.bicep",
    "--parameters", "$bicepDir\apim.bicepparam",
    "--name", "apim-deploy-$(Get-Date -Format 'yyyyMMdd-HHmmss')",
    "--verbose"
)

if ($WhatIf) {
    $deployCmd = @(
        "az", "deployment", "group", "validate",
        "--resource-group", $rg,
        "--template-file", "$bicepDir\apim.bicep",
        "--parameters", "$bicepDir\apim.bicepparam"
    )
    Write-Host "Running WHAT-IF validation only..." -ForegroundColor Yellow
}

Write-Host "`nDeploying APIM Bicep template..." -ForegroundColor Yellow
Write-Host "  Template: $bicepDir\apim.bicep" -ForegroundColor Gray
Write-Host "  RG: $rg | Region: $location" -ForegroundColor Gray
Write-Host "  APIM Developer deployment takes 30-45 minutes..." -ForegroundColor Gray
Write-Host ""

$result = & $deployCmd[0] $deployCmd[1..($deployCmd.Length-1)] 2>&1
$exitCode = $LASTEXITCODE

if ($exitCode -eq 0) {
    Write-Host "`n$([char]0x2705) APIM Deployment SUCCEEDED" -ForegroundColor Green
    Write-Host "`n--- Deployment Outputs ---" -ForegroundColor Cyan
    $latestDeploy = az deployment group list --resource-group $rg --query "[?starts_with(name,'apim-deploy')].name | [0]" -o tsv 2>&1
    if ($latestDeploy) {
        az deployment group show --resource-group $rg --name $latestDeploy --query "properties.outputs" -o json 2>&1
    }
} else {
    Write-Host "`n$([char]0x274C) APIM Deployment FAILED" -ForegroundColor Red
    Write-Host $result -ForegroundColor Red
    exit 1
}
