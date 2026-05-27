<#
.SYNOPSIS
    Test BYOM end-to-end from inside VNet (run on Jumpbox via Bastion).
.DESCRIPTION
    Creates agent with BYOM model (apim-openai-gateway/gpt-4.1),
    sends a message, waits for response, and cleans up.
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
$modelName = "apim-openai-gateway/gpt-4.1"

# --- Step 1: Create Agent ---
Write-Host "1. Creating agent with model: $modelName" -ForegroundColor Yellow
$agentBody = @{
    model = $modelName
    name = "test-byom-agent"
    instructions = "You are a helpful assistant. Reply briefly in Polish."
} | ConvertTo-Json -Compress

try {
    $agent = Invoke-RestMethod -Uri "$endpoint/agents?api-version=2025-05-01" `
        -Method POST -Headers $headers -Body $agentBody
    Write-Host "   Agent created: $($agent.id)" -ForegroundColor Green
} catch {
    Write-Host "   FAIL: $($_.Exception.Message)" -ForegroundColor Red
    if ($_.ErrorDetails) { Write-Host "   $($_.ErrorDetails.Message)" -ForegroundColor Red }
    exit 1
}

# --- Step 2: Create Thread ---
Write-Host "2. Creating thread..." -ForegroundColor Yellow
$thread = Invoke-RestMethod -Uri "$endpoint/threads?api-version=2025-05-01" `
    -Method POST -Headers $headers -Body '{}'
Write-Host "   Thread: $($thread.id)" -ForegroundColor Green

# --- Step 3: Send Message ---
Write-Host "3. Sending message..." -ForegroundColor Yellow
$msgBody = '{"role":"user","content":"Czym jest Azure API Management? Odpowiedz jednym zdaniem."}'
Invoke-RestMethod -Uri "$endpoint/threads/$($thread.id)/messages?api-version=2025-05-01" `
    -Method POST -Headers $headers -Body $msgBody | Out-Null

# --- Step 4: Run Agent ---
Write-Host "4. Running agent..." -ForegroundColor Yellow
$runBody = @{ assistant_id = $agent.id } | ConvertTo-Json -Compress
$run = Invoke-RestMethod -Uri "$endpoint/threads/$($thread.id)/runs?api-version=2025-05-01" `
    -Method POST -Headers $headers -Body $runBody

# --- Step 5: Wait for completion ---
Write-Host "5. Waiting for response..." -ForegroundColor Yellow
$maxWait = 60
$elapsed = 0
do {
    Start-Sleep -Seconds 3
    $elapsed += 3
    $runStatus = Invoke-RestMethod -Uri "$endpoint/threads/$($thread.id)/runs/$($run.id)?api-version=2025-05-01" `
        -Method GET -Headers $headers
    Write-Host "   Status: $($runStatus.status) ($($elapsed)s)"
} while ($runStatus.status -in @("queued","in_progress") -and $elapsed -lt $maxWait)

# --- Step 6: Get Response ---
if ($runStatus.status -eq "completed") {
    $messages = Invoke-RestMethod -Uri "$endpoint/threads/$($thread.id)/messages?api-version=2025-05-01" `
        -Method GET -Headers $headers
    $reply = ($messages.data | Where-Object { $_.role -eq "assistant" } | Select-Object -First 1).content[0].text.value

    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host "  BYOM RESPONSE:" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host $reply
    Write-Host "`n$([char]0x2705) BYOM E2E TEST: PASS" -ForegroundColor Green
    Write-Host "  Model: $modelName" -ForegroundColor Gray
    Write-Host "  Flow: Agent -> APIM (Internal VNet) -> Foundry OpenAI (PE)" -ForegroundColor Gray
} else {
    Write-Host "`n$([char]0x274C) BYOM E2E TEST: FAIL" -ForegroundColor Red
    Write-Host "  Final status: $($runStatus.status)" -ForegroundColor Red
    if ($runStatus.last_error) {
        Write-Host "  Error: $($runStatus.last_error.message)" -ForegroundColor Red
    }
}

# --- Cleanup ---
Write-Host "`n6. Cleanup..." -ForegroundColor Yellow
try {
    Invoke-RestMethod -Uri "$endpoint/agents/$($agent.id)?api-version=2025-05-01" `
        -Method DELETE -Headers $headers | Out-Null
    Write-Host "   Agent deleted." -ForegroundColor Green
} catch {
    Write-Host "   Warning: cleanup failed: $($_.Exception.Message)" -ForegroundColor Yellow
}
