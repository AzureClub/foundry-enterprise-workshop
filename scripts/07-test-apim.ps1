<#
.SYNOPSIS
    Test APIM: VNet mode, MI, RBAC, DNS, APIs, connectivity.
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "$PSScriptRoot\..\config\test-config.json"
)

$ErrorActionPreference = "Stop"
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rg = $config.resource_group

$results = @()
$pass = 0; $fail = 0; $warn = 0

function Add-Result($test, $status, $detail) {
    $icon = switch ($status) { "PASS" { [char]0x2705 } "FAIL" { [char]0x274C } "WARN" { [char]0x26A0 } }
    $script:results += [PSCustomObject]@{ Icon=$icon; Status=$status; Test=$test; Detail=$detail }
    switch ($status) { "PASS" { $script:pass++ } "FAIL" { $script:fail++ } "WARN" { $script:warn++ } }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  APIM VALIDATION" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# --- Discover APIM ---
$apimJson = az apim list --resource-group $rg --query "[0]" -o json 2>&1 | ConvertFrom-Json
if (-not $apimJson) {
    Write-Host "ERROR: APIM not found in $rg." -ForegroundColor Red
    exit 1
}
$apimName = $apimJson.name
Write-Host "APIM: $apimName" -ForegroundColor Green

# --- 1. APIM exists and is Developer tier ---
Write-Host "Checking APIM SKU..." -ForegroundColor Yellow
$skuName = $apimJson.sku.name
if ($skuName -eq "Developer") {
    Add-Result "APIM SKU" "PASS" "Developer (capacity: $($apimJson.sku.capacity))"
} else {
    Add-Result "APIM SKU" "WARN" "Expected Developer, got $skuName"
}

# --- 2. VNet mode is Internal ---
Write-Host "Checking VNet mode..." -ForegroundColor Yellow
$vnetType = $apimJson.virtualNetworkType
if ($vnetType -eq "Internal") {
    Add-Result "VNet Mode" "PASS" "Internal"
} else {
    Add-Result "VNet Mode" "FAIL" "Expected Internal, got $vnetType"
}

# --- 3. System Managed Identity ---
Write-Host "Checking Managed Identity..." -ForegroundColor Yellow
$miType = $apimJson.identity.type
if ($miType -like "*SystemAssigned*") {
    Add-Result "Managed Identity" "PASS" "Type: $miType, PrincipalId: $($apimJson.identity.principalId)"
} else {
    Add-Result "Managed Identity" "FAIL" "System MI not enabled. Type: $miType"
}

# --- 4. VNet Subnet configuration ---
Write-Host "Checking subnet binding..." -ForegroundColor Yellow
$subnetId = $apimJson.virtualNetworkConfiguration.subnetResourceId
$expectedSubnet = $config.vnet.apim_subnet.name
if ($subnetId -like "*$expectedSubnet*") {
    Add-Result "Subnet Binding" "PASS" "$expectedSubnet"
} else {
    Add-Result "Subnet Binding" "FAIL" "Expected $expectedSubnet, got: $subnetId"
}

# --- 5. NSG on APIM subnet ---
Write-Host "Checking NSG on APIM subnet..." -ForegroundColor Yellow
try {
    $subnet = az network vnet subnet show --vnet-name $config.vnet.name --name $expectedSubnet --resource-group $rg -o json 2>&1 | ConvertFrom-Json
    if ($subnet.networkSecurityGroup) {
        $nsgName = $subnet.networkSecurityGroup.id.Split('/')[-1]
        Add-Result "NSG on APIM Subnet" "PASS" $nsgName

        $nsgRules = az network nsg rule list --nsg-name $nsgName --resource-group $rg -o json 2>&1 | ConvertFrom-Json
        $mgmtRule = $nsgRules | Where-Object { $_.destinationPortRange -eq "3443" -and $_.access -eq "Allow" }
        if ($mgmtRule) {
            Add-Result "NSG Rule: Management (3443)" "PASS" "Allow from $($mgmtRule.sourceAddressPrefix)"
        } else {
            Add-Result "NSG Rule: Management (3443)" "FAIL" "Missing Allow rule for port 3443"
        }
    } else {
        Add-Result "NSG on APIM Subnet" "FAIL" "No NSG attached"
    }
} catch {
    Add-Result "NSG on APIM Subnet" "FAIL" "Error: $($_.Exception.Message)"
}

# --- 6. RBAC: APIM MI → Cognitive Services OpenAI User ---
Write-Host "Checking RBAC on Foundry account..." -ForegroundColor Yellow
$aiAccount = az cognitiveservices account list --resource-group $rg --query "[0]" -o json 2>&1 | ConvertFrom-Json
$apimPrincipalId = $apimJson.identity.principalId
$openaiUserRole = $config.rbac_roles.cognitive_services_openai_user

try {
    $roleAssignments = az role assignment list --scope $aiAccount.id --assignee $apimPrincipalId -o json 2>&1 | ConvertFrom-Json
    $hasRole = $roleAssignments | Where-Object { $_.roleDefinitionId -like "*$openaiUserRole*" }
    if ($hasRole) {
        Add-Result "RBAC: Cognitive Services OpenAI User" "PASS" "Assigned to APIM MI ($apimPrincipalId)"
    } else {
        Add-Result "RBAC: Cognitive Services OpenAI User" "FAIL" "NOT assigned to APIM MI"
    }
} catch {
    Add-Result "RBAC: Cognitive Services OpenAI User" "WARN" "Error checking: $($_.Exception.Message)"
}

# --- 7. Private DNS zone (azure-api.net) ---
Write-Host "Checking Private DNS zone..." -ForegroundColor Yellow
try {
    $dnsZone = az network private-dns zone show --name "azure-api.net" --resource-group $rg -o json 2>&1 | ConvertFrom-Json
    if ($dnsZone) {
        Add-Result "DNS Zone: azure-api.net" "PASS" "Exists"

        $links = az network private-dns link vnet list --zone-name "azure-api.net" --resource-group $rg -o json 2>&1 | ConvertFrom-Json
        $linkedToVnet = $links | Where-Object { $_.virtualNetwork.id -like "*$($config.vnet.name)*" }
        if ($linkedToVnet) {
            Add-Result "DNS Zone VNet Link" "PASS" "Linked to $($config.vnet.name)"
        } else {
            Add-Result "DNS Zone VNet Link" "FAIL" "NOT linked to $($config.vnet.name)"
        }

        $aRecord = az network private-dns record-set a show --zone-name "azure-api.net" --name $apimName --resource-group $rg -o json 2>&1 | ConvertFrom-Json
        if ($aRecord -and $aRecord.aRecords) {
            Add-Result "DNS A Record: $apimName" "PASS" "IP: $($aRecord.aRecords[0].ipv4Address)"
        } else {
            Add-Result "DNS A Record: $apimName" "WARN" "No A record for gateway"
        }
    }
} catch {
    Add-Result "DNS Zone: azure-api.net" "FAIL" "Not found"
}

# --- 8. APIs imported ---
Write-Host "Checking imported APIs..." -ForegroundColor Yellow
try {
    $apis = az apim api list --service-name $apimName --resource-group $rg --query "[?apiId!='echo-api'].{name:displayName, path:path, id:apiId}" -o json 2>&1 | ConvertFrom-Json
    $openaiApi = $apis | Where-Object { $_.id -like "*openai*" -or $_.path -like "*openai*" }
    $agentApi = $apis | Where-Object { $_.id -like "*agent*" -or $_.path -like "*agent*" }

    if ($openaiApi) {
        Add-Result "API: OpenAI Chat" "PASS" "Path: /$($openaiApi.path)"
    } else {
        Add-Result "API: OpenAI Chat" "WARN" "Not imported yet (run 03-import-openapi-mcp.ps1)"
    }

    if ($agentApi) {
        Add-Result "API: Foundry Agent (MCP)" "PASS" "Path: /$($agentApi.path)"
    } else {
        Add-Result "API: Foundry Agent (MCP)" "WARN" "Not imported yet (run 03-import-openapi-mcp.ps1)"
    }
} catch {
    Add-Result "API Import Check" "WARN" "Error listing APIs: $($_.Exception.Message)"
}

# --- 9. Gateway reachability (negative test from outside VNet) ---
Write-Host "Testing gateway reachability (should be unreachable from outside VNet)..." -ForegroundColor Yellow
$gatewayUrl = $apimJson.gatewayUrl
try {
    $response = Invoke-WebRequest -Uri "$gatewayUrl/status-0123456789abcdef" -TimeoutSec 10 -ErrorAction SilentlyContinue
    Add-Result "Gateway Isolation" "FAIL" "Gateway accessible from outside VNet! HTTP $($response.StatusCode)"
} catch {
    Add-Result "Gateway Isolation" "PASS" "Gateway NOT reachable from outside VNet (expected for Internal mode)"
}

# --- Print results ---
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  APIM VALIDATION RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
foreach ($r in $results) {
    $color = switch ($r.Status) { "PASS" { "Green" } "FAIL" { "Red" } "WARN" { "Yellow" } }
    Write-Host "$($r.Icon) $($r.Status)  $($r.Test): $($r.Detail)" -ForegroundColor $color
}
Write-Host "`n--- Summary: $pass PASS, $fail FAIL, $warn WARN ---" -ForegroundColor Cyan

Write-Host "`n--- APIM Connectivity Tests (from inside VNet) ---" -ForegroundColor Yellow
Write-Host "Run from Jumpbox VM via Bastion:" -ForegroundColor Gray
Write-Host "  1. curl https://$apimName.azure-api.net/status-0123456789abcdef" -ForegroundColor Gray
Write-Host "  2. curl -X POST https://$apimName.azure-api.net/openai/deployments/$($config.foundry.model_name)/chat/completions?api-version=2024-12-01-preview -H 'Content-Type: application/json' -d '{`"messages`":[{`"role`":`"user`",`"content`":`"test`"}]}'" -ForegroundColor Gray
Write-Host "  3. curl https://$apimName.azure-api.net/agent/agents?api-version=2025-05-01-preview" -ForegroundColor Gray

if ($fail -gt 0) { exit 1 } else { exit 0 }
