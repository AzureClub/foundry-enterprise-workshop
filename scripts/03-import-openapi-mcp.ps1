<#
.SYNOPSIS
    Import OpenAI Chat Completions API into APIM with Managed Identity auth.
.DESCRIPTION
    1. Discovers APIM instance and Foundry endpoint
    2. Imports OpenAI Chat Completions API
    3. Configures MI-authenticated backend policy
    Run after 02-deploy-apim.ps1.
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "$PSScriptRoot\..\config\test-config.json"
)

$ErrorActionPreference = "Stop"
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rg = $config.resource_group
$subId = $config.subscription_id
if (-not $subId -or $subId -eq "YOUR-SUBSCRIPTION-ID") {
    $subId = az account show --query "id" -o tsv 2>&1
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  IMPORT OpenAI API into APIM" -ForegroundColor Cyan
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
Write-Host "  Foundry (OpenAI): $foundryEndpoint" -ForegroundColor Green

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
# 2. Set inbound policy — MI auth + backend URL
# ============================================================================
Write-Host "`n--- Configuring MI-authenticated backend policy ---" -ForegroundColor Yellow

$openaiPolicyXml = "<policies><inbound><base /><set-backend-service base-url=`"$foundryEndpoint/openai`" /><authentication-managed-identity resource=`"https://cognitiveservices.azure.com/`" /></inbound><backend><base /></backend><outbound><base /></outbound><on-error><base /></on-error></policies>"

$body = @{ properties = @{ format = "xml"; value = $openaiPolicyXml } } | ConvertTo-Json -Depth 5 -Compress
$bodyFile = "$env:TEMP\apim-policy-openai.json"
[System.IO.File]::WriteAllText($bodyFile, $body, [System.Text.Encoding]::UTF8)

$uri = "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apimName/apis/openai-chat/policies/policy?api-version=2024-06-01-preview"
az rest --method PUT --uri $uri --body "@$bodyFile" -o none 2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host "  $([char]0x2705) OpenAI API policy configured (MI auth)" -ForegroundColor Green
} else {
    Write-Host "  $([char]0x274C) OpenAI API policy failed" -ForegroundColor Red
    $failCount++
}

# ============================================================================
# Cleanup temp files
# ============================================================================
Remove-Item -Path $specFile, $bodyFile -Force -ErrorAction SilentlyContinue

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

Write-Host "`nBackend: $foundryEndpoint/openai" -ForegroundColor Gray
Write-Host "Auth: Managed Identity (Cognitive Services OpenAI User)" -ForegroundColor Gray
Write-Host "`nNOTE: API can only be called from inside the VNet (APIM Internal mode)." -ForegroundColor Yellow
Write-Host "Test from Jumpbox VM via Bastion or through VPN P2S." -ForegroundColor Yellow

if ($failCount -gt 0) {
    Write-Host "`n$([char]0x274C) $failCount step(s) failed." -ForegroundColor Red
    exit 1
}
