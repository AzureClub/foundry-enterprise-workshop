<#
.SYNOPSIS
    Configure BYOM (Bring Your Own Model) — connect Foundry Agent to model via APIM.
.DESCRIPTION
    1. Enables subscription key on APIM OpenAI API
    2. Creates dedicated APIM subscription for agent traffic
    3. Creates ApiManagement connection on Foundry project
    4. Verifies connection is visible in project
    
    After running this script, Foundry agents can use models through APIM
    by referencing: apim-openai-gateway/<deployment-name>
    
    Run after: 02-deploy-apim.ps1 and 03-import-openapi-mcp.ps1
.EXAMPLE
    .\11-configure-byom.ps1
    .\11-configure-byom.ps1 -ProjectName "project-lab01"
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "$PSScriptRoot\..\config\test-config.json",

    [Parameter(Mandatory=$false)]
    [string]$ProjectName = "project-agent-test",

    [Parameter(Mandatory=$false)]
    [string]$ConnectionName = "apim-openai-gateway"
)

$ErrorActionPreference = "Stop"
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rg = $config.resource_group
$subId = $config.subscription_id
if (-not $subId -or $subId -eq "YOUR-SUBSCRIPTION-ID") {
    $subId = az account show --query "id" -o tsv 2>&1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  BYOM: Connect Foundry Agent to APIM" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# --- Discover resources ---
$apimName = $config.apim.name
if (-not $apimName) {
    $apimName = az apim list --resource-group $rg --query "[0].name" -o tsv 2>&1
}
$acctName = $config.foundry.account_name
if (-not $acctName) {
    $acctName = az cognitiveservices account list --resource-group $rg --query "[0].name" -o tsv 2>&1
}
Write-Host "  APIM:     $apimName" -ForegroundColor Green
Write-Host "  Foundry:  $acctName" -ForegroundColor Green
Write-Host "  Project:  $ProjectName" -ForegroundColor Green
Write-Host "  Connection: $ConnectionName`n" -ForegroundColor Green

$failCount = 0

# ============================================================================
# 1. Enable subscription key requirement on OpenAI API
# ============================================================================
Write-Host "--- Step 1: Enable subscription key on OpenAI API ---" -ForegroundColor Yellow

az apim api update --api-id "openai-chat" --service-name $apimName -g $rg --subscription-required true -o none 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host "  $([char]0x2705) Subscription required: enabled" -ForegroundColor Green
} else {
    Write-Host "  $([char]0x274C) Failed to enable subscription key" -ForegroundColor Red
    $failCount++
}

# ============================================================================
# 2. Create APIM subscription scoped to openai-chat API
# ============================================================================
Write-Host "`n--- Step 2: Create APIM subscription for BYOM ---" -ForegroundColor Yellow

$apimSubName = "foundry-byom"
$apiScope = "/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apimName/apis/openai-chat"

$subBody = @{
    properties = @{
        displayName = "foundry-byom-agent"
        scope = $apiScope
        state = "active"
    }
} | ConvertTo-Json -Depth 5 -Compress

$subBodyFile = [System.IO.Path]::GetTempFileName()
[System.IO.File]::WriteAllText($subBodyFile, $subBody, [System.Text.Encoding]::UTF8)

$subUri = "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apimName/subscriptions/${apimSubName}?api-version=2024-06-01-preview"
az rest --method PUT --uri $subUri --body "@$subBodyFile" -o none 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "  $([char]0x2705) APIM subscription '$apimSubName' created" -ForegroundColor Green
} else {
    Write-Host "  $([char]0x274C) Failed to create APIM subscription" -ForegroundColor Red
    $failCount++
}

# Get subscription key
$keyUri = "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apimName/subscriptions/${apimSubName}/listSecrets?api-version=2024-06-01-preview"
$keys = az rest --method POST --uri $keyUri -o json 2>&1 | ConvertFrom-Json
$primaryKey = $keys.primaryKey

if ($primaryKey) {
    Write-Host "  Subscription key: $($primaryKey.Substring(0, [Math]::Min(8, $primaryKey.Length)))..." -ForegroundColor Gray
} else {
    Write-Host "  $([char]0x274C) Could not retrieve subscription key" -ForegroundColor Red
    $failCount++
}

Remove-Item $subBodyFile -Force -ErrorAction SilentlyContinue

# ============================================================================
# 3. Create BYOM connection on Foundry project
# ============================================================================
Write-Host "`n--- Step 3: Create BYOM connection on project ---" -ForegroundColor Yellow

$connectionBody = @{
    properties = @{
        category = "ApiManagement"
        target = "https://$apimName.azure-api.net/openai"
        authType = "ApiKey"
        credentials = @{
            key = $primaryKey
        }
        metadata = @{
            ApiType = "Azure"
            ResourceId = "/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apimName"
        }
    }
} | ConvertTo-Json -Depth 5 -Compress

$connBodyFile = [System.IO.Path]::GetTempFileName()
[System.IO.File]::WriteAllText($connBodyFile, $connectionBody, [System.Text.Encoding]::UTF8)

$connUri = "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$acctName/projects/$ProjectName/connections/${ConnectionName}?api-version=2025-04-01-preview"
az rest --method PUT --uri $connUri --body "@$connBodyFile" -o none 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "  $([char]0x2705) Connection '$ConnectionName' created" -ForegroundColor Green
} else {
    Write-Host "  $([char]0x274C) Failed to create connection" -ForegroundColor Red
    $failCount++
}

Remove-Item $connBodyFile -Force -ErrorAction SilentlyContinue

# ============================================================================
# 4. Verify connection
# ============================================================================
Write-Host "`n--- Step 4: Verify connection ---" -ForegroundColor Yellow

$connCheck = az rest --method GET --uri "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$acctName/projects/$ProjectName/connections/${ConnectionName}?api-version=2025-04-01-preview" -o json 2>&1 | ConvertFrom-Json

if ($connCheck.properties.category -eq "ApiManagement") {
    Write-Host "  $([char]0x2705) Connection verified:" -ForegroundColor Green
    Write-Host "    Category: $($connCheck.properties.category)" -ForegroundColor Gray
    Write-Host "    Target:   $($connCheck.properties.target)" -ForegroundColor Gray
    Write-Host "    Auth:     $($connCheck.properties.authType)" -ForegroundColor Gray
    Write-Host "    Default:  $($connCheck.properties.isDefault)" -ForegroundColor Gray
} else {
    Write-Host "  $([char]0x274C) Connection verification failed" -ForegroundColor Red
    $failCount++
}

# ============================================================================
# Summary
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  BYOM CONFIGURATION SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

Write-Host "`nConnection: $ConnectionName" -ForegroundColor White
Write-Host "Target:     https://$apimName.azure-api.net/openai" -ForegroundColor White
Write-Host "Auth:       API Key (APIM subscription)" -ForegroundColor White

$modelName = $config.foundry.model_name
if (-not $modelName) { $modelName = "gpt-4.1" }

Write-Host "`nTo use in Foundry Agent:" -ForegroundColor Yellow
Write-Host "  Model reference: $ConnectionName/$modelName" -ForegroundColor White
Write-Host "  Example: Create agent with model = '$ConnectionName/$modelName'" -ForegroundColor White

Write-Host "`nTraffic flow:" -ForegroundColor Yellow
Write-Host "  Agent -> APIM (Internal VNet) -> Foundry OpenAI (PE)" -ForegroundColor White
Write-Host "  All traffic stays within the VNet" -ForegroundColor White

if ($failCount -gt 0) {
    Write-Host "`n$([char]0x274C) $failCount step(s) failed." -ForegroundColor Red
    exit 1
} else {
    Write-Host "`n$([char]0x2705) BYOM configuration complete!" -ForegroundColor Green
}
