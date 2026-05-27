<#
.SYNOPSIS
    Test BYOM end-to-end from inside VNet (run on Jumpbox via Bastion).
.DESCRIPTION
    Creates a Prompt Agent with BYOM model (apim-openai-gateway/gpt-4.1),
    sends a message via conversations API, and verifies response.
    Must run from inside VNet (Jumpbox/Bastion or VPN).
.EXAMPLE
    .\13-test-byom-e2e.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  BYOM End-to-End Test (from VNet)" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# --- Auth ---
Write-Host "Getting access token..." -ForegroundColor Yellow
$token = az account get-access-token --resource "https://ai.azure.com" --query "accessToken" -o tsv 2>&1
if (-not $token -or $token.Length -lt 50) {
    Write-Host "ERROR: Cannot get token. Run 'az login' first." -ForegroundColor Red
    exit 1
}

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type"  = "application/json"
}

$endpoint = "https://ai-foundry-byovnet-unrkke4ibdxcm.services.ai.azure.com/api/projects/project-agent-test"
$openaiEndpoint = "$endpoint/openai/v1"
$modelName = "apim-openai-gateway/gpt-4.1"
$apiVersion = "v1"

# --- Step 1: Create Prompt Agent ---
Write-Host "1. Creating Prompt Agent with model: $modelName" -ForegroundColor Yellow

$agentBody = @{
    name = "test-byom-agent"
    definition = @{
        kind = "prompt"
        model = $modelName
        instructions = "You are a helpful assistant. Reply briefly in Polish."
    }
} | ConvertTo-Json -Depth 5 -Compress

try {
    $agent = Invoke-RestMethod -Uri "$endpoint/agents?api-version=$apiVersion" `
        -Method POST -Headers $headers -Body $agentBody
    Write-Host "   Agent created: $($agent.name)" -ForegroundColor Green
} catch {
    Write-Host "   FAIL: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "   $($_.ErrorDetails.Message)" -ForegroundColor Red }
    try {
        $reader = [System.IO.StreamReader]::new($_.Exception.Response.GetResponseStream())
        $reader.BaseStream.Position = 0
        Write-Host "   Body: $($reader.ReadToEnd())" -ForegroundColor Red
    } catch {}
    exit 1
}

# --- Step 2: Send message via /openai/v1/responses (stateless) ---
Write-Host "2. Sending message via /openai/v1/responses..." -ForegroundColor Yellow
$respBody = @{
    agent_reference = @{
        name = $agent.name
        type = "agent_reference"
    }
    input = "Czym jest Azure API Management? Odpowiedz jednym zdaniem."
} | ConvertTo-Json -Depth 5 -Compress

try {
    $response = Invoke-RestMethod -Uri "$openaiEndpoint/responses" `
        -Method POST -Headers $headers -Body $respBody
    
    # Extract reply text
    $reply = $null
    if ($response.output) {
        foreach ($item in $response.output) {
            if ($item.type -eq "message" -and $item.role -eq "assistant") {
                foreach ($c in $item.content) {
                    if ($c.type -eq "output_text") { $reply = $c.text }
                    elseif ($c.type -eq "text") { $reply = $c.text }
                }
            }
        }
    }
    if (-not $reply -and $response.choices) {
        $reply = $response.choices[0].message.content
    }
    if (-not $reply) {
        $reply = $response | ConvertTo-Json -Depth 5
    }

    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  BYOM RESPONSE:" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host $reply
    Write-Host "`n$([char]0x2705) BYOM E2E TEST: PASS" -ForegroundColor Green
    Write-Host "  Model: $modelName" -ForegroundColor Gray
    Write-Host "  Endpoint: /openai/v1/responses" -ForegroundColor Gray
    Write-Host "  Flow: Agent -> APIM (Internal VNet) -> Foundry OpenAI (PE)" -ForegroundColor Gray
} catch {
    Write-Host "`n$([char]0x274C) BYOM E2E TEST: FAIL" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "  $($_.ErrorDetails.Message)" -ForegroundColor Red }
}

# --- Cleanup ---
Write-Host "`n3. Cleanup..." -ForegroundColor Yellow
try {
    Invoke-RestMethod -Uri "$endpoint/agents/$($agent.name)?api-version=$apiVersion" `
        -Method DELETE -Headers $headers | Out-Null
    Write-Host "   Agent deleted." -ForegroundColor Green
} catch {
    Write-Host "   Warning: cleanup failed: $($_.Exception.Message)" -ForegroundColor Yellow
}
