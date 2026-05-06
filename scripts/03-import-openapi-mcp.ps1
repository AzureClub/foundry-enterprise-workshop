<#
.SYNOPSIS
    Import OpenAI and MCP-proxy APIs into APIM with Managed Identity auth.
.DESCRIPTION
    1. Discovers APIM instance and Foundry endpoint
    2. Imports OpenAI Chat Completions API
    3. Imports Foundry Agent proxy API (MCP-like)
    4. Configures MI-authenticated backend policy on both
    Run after 02-deploy-apim.ps1.
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "$PSScriptRoot\..\config\test-config.json"
)

$ErrorActionPreference = "Stop"
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rg = $config.resource_group

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  IMPORT OpenAI + MCP APIs into APIM" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# --- Discover APIM name ---
Write-Host "Discovering APIM instance..." -ForegroundColor Yellow
$apimName = az apim list --resource-group $rg --query "[0].name" -o tsv 2>&1
if ($LASTEXITCODE -ne 0 -or -not $apimName) {
    Write-Host "ERROR: APIM not found in $rg. Run 02-deploy-apim.ps1 first." -ForegroundColor Red
    exit 1
}
Write-Host "  APIM: $apimName" -ForegroundColor Green

# --- Discover Foundry endpoint ---
$aiAccount = az cognitiveservices account list --resource-group $rg --query "[0]" -o json 2>&1 | ConvertFrom-Json
$rawEndpoint = $aiAccount.properties.endpoint
if ($rawEndpoint -and $rawEndpoint -ne "") {
    $foundryEndpoint = $rawEndpoint.TrimEnd('/')
} else {
    $foundryEndpoint = "https://$($aiAccount.name).cognitiveservices.azure.com"
}
$agentEndpoint = "https://$($aiAccount.name).services.ai.azure.com"
Write-Host "  Foundry (OpenAI): $foundryEndpoint" -ForegroundColor Green
Write-Host "  Foundry (Agent):  $agentEndpoint" -ForegroundColor Green

$modelName = $config.foundry.model_name
$failCount = 0

# ============================================================================
# 1. OpenAI Chat Completions API
# ============================================================================
Write-Host "`n--- Importing OpenAI Chat Completions API ---" -ForegroundColor Yellow

$openaiSpec = @{
    openapi = "3.0.1"
    info = @{
        title = "Azure OpenAI - Chat Completions"
        version = "2024-12-01-preview"
    }
    paths = @{
        "/deployments/{deployment-id}/chat/completions" = @{
            post = @{
                operationId = "createChatCompletion"
                summary = "Creates a chat completion for the provided messages"
                parameters = @(
                    @{ name = "deployment-id"; "in" = "path"; required = $true; schema = @{ type = "string" } }
                    @{ name = "api-version"; "in" = "query"; required = $true; schema = @{ type = "string"; default = "2024-12-01-preview" } }
                )
                requestBody = @{
                    required = $true
                    content = @{
                        "application/json" = @{
                            schema = @{
                                type = "object"
                                required = @("messages")
                                properties = @{
                                    messages = @{ type = "array"; items = @{ type = "object" } }
                                    temperature = @{ type = "number" }
                                    max_tokens = @{ type = "integer" }
                                }
                            }
                        }
                    }
                }
                responses = @{
                    "200" = @{ description = "Chat completion response" }
                    "401" = @{ description = "Unauthorized" }
                    "429" = @{ description = "Rate limited" }
                }
            }
        }
    }
} | ConvertTo-Json -Depth 15

$specFile = "$env:TEMP\openai-spec.json"
$openaiSpec | Out-File -FilePath $specFile -Encoding utf8 -Force

az apim api import `
    --api-id "openai-chat" `
    --path "openai" `
    --service-name $apimName `
    --resource-group $rg `
    --specification-format OpenApi `
    --specification-path $specFile `
    --display-name "Azure OpenAI Chat Completions" `
    --protocols https `
    --subscription-required $false `
    -o none 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "  $([char]0x2705) OpenAI API imported" -ForegroundColor Green
} else {
    Write-Host "  $([char]0x274C) OpenAI API import failed" -ForegroundColor Red
    $failCount++
}

# ============================================================================
# 2. Foundry Agent Proxy API (MCP-compatible)
# ============================================================================
Write-Host "`n--- Importing Foundry Agent Proxy API ---" -ForegroundColor Yellow

$agentSpec = @{
    openapi = "3.0.1"
    info = @{
        title = "Foundry Agent Proxy (MCP)"
        version = "1.0"
        description = "Proxy to Foundry Agent Service for MCP-like scenarios"
    }
    paths = @{
        "/agents" = @{
            post = @{
                operationId = "createAgent"
                summary = "Create an agent"
                parameters = @(
                    @{ name = "api-version"; "in" = "query"; required = $true; schema = @{ type = "string"; default = "2025-05-01-preview" } }
                )
                requestBody = @{
                    content = @{
                        "application/json" = @{
                            schema = @{ type = "object" }
                        }
                    }
                }
                responses = @{ "200" = @{ description = "Agent created" } }
            }
            get = @{
                operationId = "listAgents"
                summary = "List agents"
                parameters = @(
                    @{ name = "api-version"; "in" = "query"; required = $true; schema = @{ type = "string"; default = "2025-05-01-preview" } }
                )
                responses = @{ "200" = @{ description = "Agent list" } }
            }
        }
        "/agents/{agent-id}/threads" = @{
            post = @{
                operationId = "createThread"
                summary = "Create a thread for agent conversation"
                parameters = @(
                    @{ name = "agent-id"; "in" = "path"; required = $true; schema = @{ type = "string" } }
                    @{ name = "api-version"; "in" = "query"; required = $true; schema = @{ type = "string"; default = "2025-05-01-preview" } }
                )
                requestBody = @{
                    content = @{
                        "application/json" = @{
                            schema = @{ type = "object" }
                        }
                    }
                }
                responses = @{ "200" = @{ description = "Thread created" } }
            }
        }
    }
} | ConvertTo-Json -Depth 15

$agentSpecFile = "$env:TEMP\agent-spec.json"
$agentSpec | Out-File -FilePath $agentSpecFile -Encoding utf8 -Force

az apim api import `
    --api-id "foundry-agent" `
    --path "agent" `
    --service-name $apimName `
    --resource-group $rg `
    --specification-format OpenApi `
    --specification-path $agentSpecFile `
    --display-name "Foundry Agent Proxy (MCP)" `
    --protocols https `
    --subscription-required $false `
    -o none 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "  $([char]0x2705) Agent API imported" -ForegroundColor Green
} else {
    Write-Host "  $([char]0x274C) Agent API import failed" -ForegroundColor Red
    $failCount++
}

# ============================================================================
# 3. Set inbound policies— MI auth + backend URL
# ============================================================================
Write-Host "`n--- Configuring MI-authenticated backend policies ---" -ForegroundColor Yellow

$openaiPolicy = @"
<policies>
    <inbound>
        <base />
        <set-backend-service base-url="$foundryEndpoint/openai" />
        <authentication-managed-identity resource="https://cognitiveservices.azure.com/" />
    </inbound>
    <backend><base /></backend>
    <outbound><base /></outbound>
    <on-error><base /></on-error>
</policies>
"@

$policyFile = "$env:TEMP\apim-policy-openai.xml"
$openaiPolicy | Out-File -FilePath $policyFile -Encoding utf8 -Force

az apim api policy create `
    --api-id "openai-chat" `
    --service-name $apimName `
    --resource-group $rg `
    --xml-file $policyFile `
    -o none 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "  $([char]0x2705) OpenAI API policy configured (MI auth)" -ForegroundColor Green
} else {
    Write-Host "  $([char]0x274C) OpenAI API policy failed" -ForegroundColor Red
    $failCount++
}

$agentPolicy = @"
<policies>
    <inbound>
        <base />
        <set-backend-service base-url="$agentEndpoint" />
        <authentication-managed-identity resource="https://cognitiveservices.azure.com/" />
    </inbound>
    <backend><base /></backend>
    <outbound><base /></outbound>
    <on-error><base /></on-error>
</policies>
"@

$agentPolicyFile = "$env:TEMP\apim-policy-agent.xml"
$agentPolicy | Out-File -FilePath $agentPolicyFile -Encoding utf8 -Force

az apim api policy create `
    --api-id "foundry-agent" `
    --service-name $apimName `
    --resource-group $rg `
    --xml-file $agentPolicyFile `
    -o none 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "  $([char]0x2705) Agent API policy configured (MI auth)" -ForegroundColor Green
} else {
    Write-Host "  $([char]0x274C) Agent API policy failed" -ForegroundColor Red
    $failCount++
}

# ============================================================================
# Cleanup temp files
# ============================================================================
Remove-Item -Path $specFile, $agentSpecFile, $policyFile, $agentPolicyFile -Force -ErrorAction SilentlyContinue

# ============================================================================
# Summary
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  API IMPORT SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$apis = az apim api list --service-name $apimName --resource-group $rg --query "[].{name:displayName, path:path, id:apiId}" -o json 2>&1 | ConvertFrom-Json
foreach ($api in $apis) {
    Write-Host "  API: $($api.name) | Path: /$($api.path) | ID: $($api.id)" -ForegroundColor Green
}

Write-Host "`nBackend (OpenAI): $foundryEndpoint/openai" -ForegroundColor Gray
Write-Host "Backend (Agent):  $agentEndpoint" -ForegroundColor Gray
Write-Host "Auth: Managed Identity (Cognitive Services OpenAI User + Azure AI Developer)" -ForegroundColor Gray
Write-Host "`nNOTE: APIs can only be called from inside the VNet (APIM Internal mode)." -ForegroundColor Yellow
Write-Host "Test from Jumpbox VM via Bastion or through VPN P2S." -ForegroundColor Yellow

if ($failCount -gt 0) {
    Write-Host "`n$([char]0x274C) $failCount step(s) failed." -ForegroundColor Red
    exit 1
}
