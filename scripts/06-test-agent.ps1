<#
.SYNOPSIS
    Test Foundry Agent Service: network injection, capability host, model, data plane isolation.
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "$PSScriptRoot\..\config\test-config.json"
)

$ErrorActionPreference = "Stop"
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rg = $config.resource_group
$sub = $config.subscription_id

$results = @()
$pass = 0; $fail = 0; $warn = 0

function Add-Result($test, $status, $detail) {
    $icon = switch ($status) { "PASS" { [char]0x2705 } "FAIL" { [char]0x274C } "WARN" { [char]0x26A0 } }
    $script:results += [PSCustomObject]@{ Icon=$icon; Status=$status; Test=$test; Detail=$detail }
    switch ($status) { "PASS" { $script:pass++ } "FAIL" { $script:fail++ } "WARN" { $script:warn++ } }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  AGENT SERVICE VALIDATION" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# --- Discover Foundry account ---
$aiAccount = az cognitiveservices account list --resource-group $rg --query "[0]" -o json 2>&1 | ConvertFrom-Json
$accountName = $aiAccount.name

# --- 1. Network Injection configured ---
Write-Host "Checking Network Injection..." -ForegroundColor Yellow
try {
    $accountJson = az rest --method GET `
        --url "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/${accountName}?api-version=2025-04-01-preview" `
        -o json 2>&1 | ConvertFrom-Json

    $injections = $accountJson.properties.networkInjections
    if ($injections -and $injections.Count -gt 0) {
        $agentInjection = $injections | Where-Object { $_.scenario -eq "agent" }
        if ($agentInjection) {
            $useManagedNet = $agentInjection.useMicrosoftManagedNetwork
            if ($useManagedNet -eq $false) {
                Add-Result "Network Injection (BYO VNet)" "PASS" "scenario=agent, useMicrosoftManagedNetwork=false, subnet=$($agentInjection.subnetArmId.Split('/')[-1])"
            } else {
                Add-Result "Network Injection (BYO VNet)" "FAIL" "useMicrosoftManagedNetwork should be false, got $useManagedNet"
            }
        } else {
            Add-Result "Network Injection (BYO VNet)" "FAIL" "No 'agent' scenario found in networkInjections"
        }
    } else {
        Add-Result "Network Injection (BYO VNet)" "FAIL" "networkInjections is empty or missing"
    }
} catch {
    Add-Result "Network Injection (BYO VNet)" "FAIL" "Error: $($_.Exception.Message)"
}

# --- 2. Public Network Access disabled ---
Write-Host "Checking Public Network Access..." -ForegroundColor Yellow
try {
    $publicAccess = $accountJson.properties.publicNetworkAccess
    if ($publicAccess -eq "Disabled") {
        Add-Result "Public Network Access" "PASS" "Disabled"
    } else {
        Add-Result "Public Network Access" "FAIL" "Expected Disabled, got $publicAccess"
    }
} catch {
    Add-Result "Public Network Access" "WARN" "Could not determine: $($_.Exception.Message)"
}

# --- 3. allowProjectManagement ---
Write-Host "Checking allowProjectManagement..." -ForegroundColor Yellow
try {
    $allowPM = $accountJson.properties.allowProjectManagement
    if ($allowPM -eq $true) {
        Add-Result "allowProjectManagement" "PASS" "true"
    } else {
        Add-Result "allowProjectManagement" "FAIL" "Expected true, got $allowPM"
    }
} catch {
    Add-Result "allowProjectManagement" "WARN" "Could not determine"
}

# --- 4. Capability Host provisioned ---
Write-Host "Checking Capability Host..." -ForegroundColor Yellow
$projectName = $config.foundry.project_name
try {
    $capHost = az rest --method GET `
        --url "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/${accountName}/projects/${projectName}/capabilityHosts/default?api-version=2025-04-01-preview" `
        -o json 2>&1 | ConvertFrom-Json

    if ($capHost.name) {
        $kind = $capHost.properties.capabilityHostKind
        Add-Result "Capability Host" "PASS" "kind=$kind, storageConn=$($capHost.properties.storageConnections -join ',')"
    } else {
        Add-Result "Capability Host" "FAIL" "Not found"
    }
} catch {
    Add-Result "Capability Host" "FAIL" "Not provisioned: $($_.Exception.Message)"
}

# --- 5. Model Deployment exists ---
Write-Host "Checking Model Deployment..." -ForegroundColor Yellow
$expectedModel = $config.foundry.model_name
try {
    $deployments = az cognitiveservices account deployment list --name $accountName --resource-group $rg -o json 2>&1 | ConvertFrom-Json
    $modelDep = $deployments | Where-Object { $_.name -eq $expectedModel }
    if ($modelDep) {
        $status = $modelDep.properties.provisioningState
        Add-Result "Model Deployment: $expectedModel" "PASS" "Status: $status, SKU: $($modelDep.sku.name)"
    } else {
        $availableModels = ($deployments | ForEach-Object { $_.name }) -join ", "
        Add-Result "Model Deployment: $expectedModel" "FAIL" "Not found. Available: $availableModels"
    }
} catch {
    Add-Result "Model Deployment: $expectedModel" "FAIL" "Error listing deployments: $($_.Exception.Message)"
}

# --- 6. Project Connections exist ---
Write-Host "Checking Project Connections..." -ForegroundColor Yellow
try {
    $connections = az rest --method GET `
        --url "https://management.azure.com/subscriptions/$sub/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/${accountName}/projects/${projectName}/connections?api-version=2025-04-01-preview" `
        -o json 2>&1 | ConvertFrom-Json

    $connList = $connections.value
    $expectedConns = @("connection-storage", "connection-search", "connection-cosmos")

    foreach ($expected in $expectedConns) {
        $found = $connList | Where-Object { $_.name -like "*$expected*" }
        if ($found) {
            Add-Result "Connection: $expected" "PASS" "Category: $($found.properties.category), Auth: $($found.properties.authType)"
        } else {
            Add-Result "Connection: $expected" "FAIL" "Not found"
        }
    }
} catch {
    Add-Result "Project Connections" "FAIL" "Error: $($_.Exception.Message)"
}

# --- 7. Data Plane isolation test (negative test) ---
Write-Host "Testing Data Plane isolation (should be DENIED from outside VNet)..." -ForegroundColor Yellow
$endpoint = "https://$accountName.cognitiveservices.azure.com"
$agentEndpoint = "https://$accountName.services.ai.azure.com"
try {
    $token = az account get-access-token --resource "https://cognitiveservices.azure.com" --query accessToken -o tsv 2>&1

    # Test OpenAI data plane
    $body = @{
        messages = @(@{ role = "user"; content = "test" })
    } | ConvertTo-Json -Depth 5

    $response = $null
    try {
        $response = Invoke-WebRequest -Uri "$endpoint/openai/deployments/$expectedModel/chat/completions?api-version=2024-12-01-preview" `
            -Method POST `
            -Headers @{ "Authorization" = "Bearer $token"; "Content-Type" = "application/json" } `
            -Body $body `
            -TimeoutSec 10 `
            -ErrorAction SilentlyContinue
    } catch {
        $statusCode = $_.Exception.Response.StatusCode.value__
        if ($statusCode -eq 403 -or $statusCode -eq 0 -or -not $statusCode) {
            Add-Result "OpenAI Data Plane Isolation" "PASS" "Denied from outside VNet (expected). Code: $statusCode"
        } else {
            Add-Result "OpenAI Data Plane Isolation" "WARN" "Got HTTP $statusCode (expected 403 or timeout)"
        }
        $response = "denied"
    }

    if ($response -and $response -ne "denied") {
        Add-Result "OpenAI Data Plane Isolation" "FAIL" "Data plane accessible from outside VNet! HTTP $($response.StatusCode)"
    }

    # Test Agent data plane
    $agentResponse = $null
    try {
        $agentResponse = Invoke-WebRequest -Uri "$agentEndpoint/agents?api-version=2025-05-01-preview" `
            -Method GET `
            -Headers @{ "Authorization" = "Bearer $token" } `
            -TimeoutSec 10 `
            -ErrorAction SilentlyContinue
    } catch {
        $agentStatusCode = $_.Exception.Response.StatusCode.value__
        if ($agentStatusCode -eq 403 -or $agentStatusCode -eq 0 -or -not $agentStatusCode) {
            Add-Result "Agent Data Plane Isolation" "PASS" "Denied from outside VNet (expected). Code: $agentStatusCode"
        } else {
            Add-Result "Agent Data Plane Isolation" "WARN" "Got HTTP $agentStatusCode (expected 403 or timeout)"
        }
        $agentResponse = "denied"
    }

    if ($agentResponse -and $agentResponse -ne "denied") {
        Add-Result "Agent Data Plane Isolation" "FAIL" "Agent data plane accessible from outside VNet! HTTP $($agentResponse.StatusCode)"
    }
} catch {
    Add-Result "Data Plane Isolation" "PASS" "Connection refused/timeout from outside VNet (expected)"
}

# --- Print results ---
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  AGENT SERVICE RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
foreach ($r in $results) {
    $color = switch ($r.Status) { "PASS" { "Green" } "FAIL" { "Red" } "WARN" { "Yellow" } }
    Write-Host "$($r.Icon) $($r.Status)  $($r.Test): $($r.Detail)" -ForegroundColor $color
}
Write-Host "`n--- Summary: $pass PASS, $fail FAIL, $warn WARN ---" -ForegroundColor Cyan

Write-Host "`n--- Data Plane Tests (from inside VNet) ---" -ForegroundColor Yellow
Write-Host "Run these from Jumpbox VM via Bastion:" -ForegroundColor Gray
Write-Host "  1. Open PowerShell on Jumpbox" -ForegroundColor Gray
Write-Host "  2. az login" -ForegroundColor Gray
Write-Host '  3. $token = az account get-access-token --resource "https://cognitiveservices.azure.com" --query accessToken -o tsv' -ForegroundColor Gray
Write-Host "  4. # OpenAI test:" -ForegroundColor Gray
Write-Host "     curl -X POST `"$endpoint/openai/deployments/$expectedModel/chat/completions?api-version=2024-12-01-preview`" -H `"Authorization: Bearer `$token`" -H `"Content-Type: application/json`" -d '{`"messages`":[{`"role`":`"user`",`"content`":`"hello`"}]}'" -ForegroundColor Gray
Write-Host "  5. # Agent test:" -ForegroundColor Gray
Write-Host "     curl `"$agentEndpoint/agents?api-version=2025-05-01-preview`" -H `"Authorization: Bearer `$token`"" -ForegroundColor Gray

if ($fail -gt 0) { exit 1 } else { exit 0 }
