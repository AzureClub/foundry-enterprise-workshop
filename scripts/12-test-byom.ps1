<#
.SYNOPSIS
    Test BYOM (Bring Your Own Model) — verify Foundry agent can use model through APIM.
.DESCRIPTION
    Validates:
    1. APIM subscription exists and is active
    2. Foundry project connection exists (ApiManagement type)
    3. Connection target matches APIM gateway
    4. APIM OpenAI API has subscription requirement
    5. APIM can reach Foundry backend (via APIM MI)
    
    Run after: 11-configure-byom.ps1
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
Write-Host "  TEST: BYOM Configuration" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

$apimName = $config.apim.name
if (-not $apimName) {
    $apimName = az apim list --resource-group $rg --query "[0].name" -o tsv 2>&1
}
$acctName = $config.foundry.account_name
if (-not $acctName) {
    $acctName = az cognitiveservices account list --resource-group $rg --query "[0].name" -o tsv 2>&1
}

$pass = 0; $fail = 0; $warn = 0
$results = @()

function Test-Result {
    param([string]$Name, [bool]$Passed, [string]$Detail = "", [bool]$IsWarn = $false)
    if ($Passed) {
        Write-Host "  $([char]0x2705) PASS: $Name" -ForegroundColor Green
        $script:pass++
        $script:results += @{ name=$Name; status="PASS"; detail=$Detail }
    } elseif ($IsWarn) {
        Write-Host "  $([char]0x26A0) WARN: $Name" -ForegroundColor Yellow
        if ($Detail) { Write-Host "         $Detail" -ForegroundColor Yellow }
        $script:warn++
        $script:results += @{ name=$Name; status="WARN"; detail=$Detail }
    } else {
        Write-Host "  $([char]0x274C) FAIL: $Name" -ForegroundColor Red
        if ($Detail) { Write-Host "         $Detail" -ForegroundColor Red }
        $script:fail++
        $script:results += @{ name=$Name; status="FAIL"; detail=$Detail }
    }
}

# ============================================================================
# Test 1: APIM subscription exists
# ============================================================================
Write-Host "--- APIM Subscription ---" -ForegroundColor Yellow

$subUri = "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apimName/subscriptions/foundry-byom?api-version=2024-06-01-preview"
try {
    $apimSub = az rest --method GET --uri $subUri -o json 2>&1 | ConvertFrom-Json
    $subState = $apimSub.properties.state
    Test-Result "APIM subscription 'foundry-byom' exists" ($subState -eq "active") "State: $subState"
} catch {
    Test-Result "APIM subscription 'foundry-byom' exists" $false "Subscription not found"
}

# ============================================================================
# Test 2: APIM subscription has valid key
# ============================================================================
$keyUri = "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apimName/subscriptions/foundry-byom/listSecrets?api-version=2024-06-01-preview"
try {
    $keys = az rest --method POST --uri $keyUri -o json 2>&1 | ConvertFrom-Json
    Test-Result "APIM subscription key available" ($null -ne $keys.primaryKey)
} catch {
    Test-Result "APIM subscription key available" $false "Cannot retrieve key"
}

# ============================================================================
# Test 3: OpenAI API requires subscription
# ============================================================================
Write-Host "`n--- APIM API Configuration ---" -ForegroundColor Yellow

$apiInfo = az apim api show --api-id "openai-chat" --service-name $apimName -g $rg -o json 2>&1 | ConvertFrom-Json
$subRequired = $apiInfo.subscriptionRequired
Test-Result "OpenAI API requires subscription key" ($subRequired -eq $true) "subscriptionRequired: $subRequired"

# ============================================================================
# Test 4: Foundry connection exists
# ============================================================================
Write-Host "`n--- Foundry Project Connection ---" -ForegroundColor Yellow

$connUri = "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$acctName/projects/$ProjectName/connections/${ConnectionName}?api-version=2025-04-01-preview"
try {
    $conn = az rest --method GET --uri $connUri -o json 2>&1 | ConvertFrom-Json
    Test-Result "Connection '$ConnectionName' exists" ($null -ne $conn.name)
} catch {
    Test-Result "Connection '$ConnectionName' exists" $false "Connection not found"
}

# ============================================================================
# Test 5: Connection category is ApiManagement
# ============================================================================
if ($conn) {
    $category = $conn.properties.category
    Test-Result "Connection category is 'ApiManagement'" ($category -eq "ApiManagement") "Category: $category"
}

# ============================================================================
# Test 6: Connection target matches APIM gateway
# ============================================================================
if ($conn) {
    $target = $conn.properties.target
    $expectedTarget = "https://$apimName.azure-api.net/openai"
    Test-Result "Connection target matches APIM" ($target -eq $expectedTarget) "Target: $target"
}

# ============================================================================
# Test 7: Connection auth type
# ============================================================================
if ($conn) {
    $authType = $conn.properties.authType
    Test-Result "Connection auth type is 'ApiKey'" ($authType -eq "ApiKey") "AuthType: $authType"
}

# ============================================================================
# Test 8: APIM has MI-authenticated backend policy
# ============================================================================
Write-Host "`n--- APIM Backend Policy ---" -ForegroundColor Yellow

$policyUri = "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apimName/apis/openai-chat/policies/policy?api-version=2024-06-01-preview"
try {
    $token = az account get-access-token --query "accessToken" -o tsv 2>&1
    $headers = @{ Authorization = "Bearer $token" }
    $resp = Invoke-RestMethod -Uri $policyUri -Headers $headers -Method GET
    $policyStr = $resp.properties.value
    $hasMI = $policyStr -match "authentication-managed-identity"
    $hasBackend = $policyStr -match "set-backend-service"
    Test-Result "APIM policy: set-backend-service configured" $hasBackend
    Test-Result "APIM policy: MI authentication enabled" $hasMI
} catch {
    Test-Result "APIM backend policy readable" $false "Cannot read policy: $_"
}

# ============================================================================
# Test 9: APIM MI has RBAC to Foundry
# ============================================================================
Write-Host "`n--- RBAC Verification ---" -ForegroundColor Yellow

$apimInfo = az apim show --name $apimName -g $rg -o json 2>&1 | ConvertFrom-Json
$apimPrincipalId = $apimInfo.identity.principalId
$cogServicesRole = "5e0bd9bd-7b93-4f28-af87-19fc36ad61bd" # Cognitive Services OpenAI User

$roleAssignments = az role assignment list --assignee $apimPrincipalId --all -o json 2>&1 | ConvertFrom-Json
$hasOpenAIRole = $roleAssignments | Where-Object { $_.roleDefinitionName -eq "Cognitive Services OpenAI User" }
Test-Result "APIM MI has 'Cognitive Services OpenAI User' role" ($null -ne $hasOpenAIRole)

# ============================================================================
# Test 10: Traffic flow check (APIM Internal + connection via VNet)
# ============================================================================
Write-Host "`n--- Network Path ---" -ForegroundColor Yellow

$apimVnetType = $apimInfo.virtualNetworkType
Test-Result "APIM is in VNet mode" ($apimVnetType -eq "Internal" -or $apimVnetType -eq "External") "Mode: $apimVnetType"

# Check connection metadata has APIM ResourceId
if ($conn -and $conn.properties.metadata) {
    $resId = $conn.properties.metadata.ResourceId
    $hasResId = $resId -match $apimName
    Test-Result "Connection metadata references APIM resource" $hasResId
} else {
    Test-Result "Connection metadata references APIM resource" $false -IsWarn $true -Detail "No metadata"
}

# ============================================================================
# Summary
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  BYOM TEST RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$modelName = $config.foundry.model_name
if (-not $modelName) { $modelName = "gpt-4.1" }

Write-Host "  $([char]0x2705) PASS: $pass" -ForegroundColor Green
if ($warn -gt 0) { Write-Host "  $([char]0x26A0) WARN: $warn" -ForegroundColor Yellow }
if ($fail -gt 0) { Write-Host "  $([char]0x274C) FAIL: $fail" -ForegroundColor Red }
Write-Host "  Total: $($pass + $warn + $fail)" -ForegroundColor White

if ($fail -eq 0) {
    Write-Host "`n$([char]0x2705) BYOM ready! Use model: $ConnectionName/$modelName" -ForegroundColor Green
    Write-Host "  Flow: Agent -> $ConnectionName -> APIM (VNet) -> Foundry OpenAI (PE)" -ForegroundColor Gray
} else {
    Write-Host "`n$([char]0x274C) $fail test(s) failed. Fix issues and rerun." -ForegroundColor Red
    exit 1
}
