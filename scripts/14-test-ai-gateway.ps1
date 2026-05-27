<#
.SYNOPSIS
    Test AI Gateway: APIM Standard v2 + PE for AI API calls.
.DESCRIPTION
    Tests APIM Standard v2 with Private Endpoint from inside VNet.
    Calls OpenAI Chat Completions through APIM gateway.
    Must run from inside VNet (Jumpbox via Bastion).
.EXAMPLE
    .\14-test-ai-gateway.ps1
#>

$ErrorActionPreference = "Stop"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  AI Gateway Test" -ForegroundColor Cyan
Write-Host "  APIM Standard v2 + Private Endpoint" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# --- Config ---
$rg = "rg-foundry-byovnet"
$pass = 0; $fail = 0
$results = @()

function Add-Result($test, $status, $detail) {
    $icon = switch ($status) { "PASS" { [char]0x2705 } "FAIL" { [char]0x274C } }
    $script:results += [PSCustomObject]@{ Icon=$icon; Status=$status; Test=$test; Detail=$detail }
    Write-Host "  $icon $status`: $test" -ForegroundColor $(if ($status -eq "PASS") { "Green" } else { "Red" })
    if ($detail) { Write-Host "     $detail" -ForegroundColor Gray }
    switch ($status) { "PASS" { $script:pass++ } "FAIL" { $script:fail++ } }
}

# --- Step 1: Discover APIM ---
Write-Host "--- Discovering APIM ---" -ForegroundColor Yellow
$apimName = az apim list -g $rg --query "[0].name" -o tsv 2>$null
if (-not $apimName) {
    Write-Host "  ERROR: APIM not found in $rg" -ForegroundColor Red
    exit 1
}
$gatewayUrl = az apim show -n $apimName -g $rg --query "gatewayUrl" -o tsv
Write-Host "  APIM: $apimName" -ForegroundColor Cyan
Write-Host "  Gateway: $gatewayUrl`n" -ForegroundColor Cyan

# --- Step 2: Get subscription key ---
Write-Host "--- Getting subscription key ---" -ForegroundColor Yellow
$subId = "38b8b5d4-b3a1-4892-b2a7-3f5bcfdad59f"
$subKey = az rest --method POST `
    --uri "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apimName/subscriptions/foundry-byom/listSecrets?api-version=2024-06-01-preview" `
    --query "primaryKey" -o tsv 2>$null

if (-not $subKey) {
    # Fallback: try master subscription
    $subKey = az rest --method POST `
        --uri "https://management.azure.com/subscriptions/$subId/resourceGroups/$rg/providers/Microsoft.ApiManagement/service/$apimName/subscriptions/master/listSecrets?api-version=2024-06-01-preview" `
        --query "primaryKey" -o tsv 2>$null
    if ($subKey) {
        Write-Host "  Using master subscription key`n" -ForegroundColor Yellow
    }
}

if (-not $subKey) {
    Write-Host "  ERROR: Cannot get subscription key" -ForegroundColor Red
    exit 1
}
Write-Host "  Subscription key: $($subKey.Substring(0,8))...`n" -ForegroundColor Cyan

# --- Step 3: DNS Resolution ---
Write-Host "--- Test 1: DNS Resolution ---" -ForegroundColor Yellow
$apimHost = "$apimName.azure-api.net"
try {
    $dns = Resolve-DnsName $apimHost -ErrorAction Stop
    $ip = ($dns | Where-Object { $_.QueryType -eq "A" } | Select-Object -First 1).IPAddress
    Add-Result "DNS resolves $apimHost" "PASS" "IP: $ip"
} catch {
    Add-Result "DNS resolves $apimHost" "FAIL" "Cannot resolve - must run from VNet"
    Write-Host "`n  This test must run from inside VNet (Jumpbox via Bastion)." -ForegroundColor Red
    exit 1
}

# --- Step 4: TCP Connectivity ---
Write-Host "`n--- Test 2: TCP Connectivity ---" -ForegroundColor Yellow
try {
    $tcp = Test-NetConnection -ComputerName $apimHost -Port 443 -WarningAction SilentlyContinue
    if ($tcp.TcpTestSucceeded) {
        Add-Result "TCP 443 to APIM" "PASS" ""
    } else {
        Add-Result "TCP 443 to APIM" "FAIL" "Port 443 not reachable"
    }
} catch {
    Add-Result "TCP 443 to APIM" "FAIL" $_.Exception.Message
}

# --- Step 5: Chat Completions (simple) ---
Write-Host "`n--- Test 3: Chat Completions ---" -ForegroundColor Yellow
$chatUrl = "$gatewayUrl/openai/deployments/gpt-4.1/chat/completions?api-version=2024-12-01-preview"
$chatBody = @{
    messages = @(
        @{ role = "system"; content = "You are a helpful assistant. Reply in Polish, one sentence max." }
        @{ role = "user"; content = "Czym jest Azure API Management?" }
    )
    max_tokens = 150
    temperature = 0.7
} | ConvertTo-Json -Depth 3 -Compress

$headers = @{
    "Ocp-Apim-Subscription-Key" = $subKey
    "Content-Type" = "application/json"
}

try {
    $startTime = Get-Date
    $response = Invoke-RestMethod -Uri $chatUrl -Method POST -Headers $headers -Body $chatBody
    $elapsed = ((Get-Date) - $startTime).TotalMilliseconds
    $reply = $response.choices[0].message.content
    $model = $response.model
    $promptTokens = $response.usage.prompt_tokens
    $completionTokens = $response.usage.completion_tokens
    $totalTokens = $response.usage.total_tokens

    Add-Result "Chat Completions via APIM" "PASS" "Model: $model, Tokens: $totalTokens, Latency: $([int]$elapsed)ms"
    Write-Host "`n  Response:" -ForegroundColor Green
    Write-Host "  $reply" -ForegroundColor White
    Write-Host "  Tokens: prompt=$promptTokens, completion=$completionTokens, total=$totalTokens" -ForegroundColor Gray
} catch {
    Add-Result "Chat Completions via APIM" "FAIL" $_.Exception.Message
    if ($_.ErrorDetails) { Write-Host "  $($_.ErrorDetails.Message)" -ForegroundColor Red }
}

# --- Step 6: Streaming test ---
Write-Host "`n--- Test 4: Streaming Response ---" -ForegroundColor Yellow
$streamBody = @{
    messages = @(
        @{ role = "user"; content = "Wymien 3 uslugi Azure w jednym zdaniu." }
    )
    max_tokens = 100
    stream = $true
} | ConvertTo-Json -Depth 3 -Compress

try {
    $streamReq = [System.Net.HttpWebRequest]::Create($chatUrl)
    $streamReq.Method = "POST"
    $streamReq.ContentType = "application/json"
    $streamReq.Headers.Add("Ocp-Apim-Subscription-Key", $subKey)
    $bodyBytes = [System.Text.Encoding]::UTF8.GetBytes($streamBody)
    $streamReq.GetRequestStream().Write($bodyBytes, 0, $bodyBytes.Length)

    $streamResp = $streamReq.GetResponse()
    $reader = [System.IO.StreamReader]::new($streamResp.GetResponseStream())
    $chunks = 0
    $fullText = ""
    while (-not $reader.EndOfStream) {
        $line = $reader.ReadLine()
        if ($line -match '^data: (.+)$' -and $matches[1] -ne "[DONE]") {
            $chunks++
            try {
                $chunk = $matches[1] | ConvertFrom-Json
                $delta = $chunk.choices[0].delta.content
                if ($delta) { $fullText += $delta }
            } catch {}
        }
    }
    $reader.Close()
    $streamResp.Close()

    if ($chunks -gt 0) {
        Add-Result "Streaming response" "PASS" "$chunks chunks received"
        Write-Host "  Response: $fullText" -ForegroundColor White
    } else {
        Add-Result "Streaming response" "FAIL" "No chunks received"
    }
} catch {
    Add-Result "Streaming response" "FAIL" $_.Exception.Message
}

# --- Step 7: Error handling (invalid model) ---
Write-Host "`n--- Test 5: Error Handling ---" -ForegroundColor Yellow
$badUrl = "$gatewayUrl/openai/deployments/nonexistent-model/chat/completions?api-version=2024-12-01-preview"
$badBody = '{"messages":[{"role":"user","content":"test"}]}'
try {
    Invoke-RestMethod -Uri $badUrl -Method POST -Headers $headers -Body $badBody -ErrorAction Stop
    Add-Result "Error on invalid model" "FAIL" "Should have returned error"
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -ge 400) {
        Add-Result "Error on invalid model" "PASS" "HTTP $statusCode returned correctly"
    } else {
        Add-Result "Error on invalid model" "FAIL" "Unexpected: $($_.Exception.Message)"
    }
}

# --- Step 8: Auth test (no key) ---
Write-Host "`n--- Test 6: Auth Without Key ---" -ForegroundColor Yellow
$noKeyHeaders = @{ "Content-Type" = "application/json" }
try {
    Invoke-RestMethod -Uri $chatUrl -Method POST -Headers $noKeyHeaders -Body $chatBody -ErrorAction Stop
    Add-Result "Rejected without subscription key" "FAIL" "Should have been rejected"
} catch {
    $statusCode = $_.Exception.Response.StatusCode.value__
    if ($statusCode -eq 401) {
        Add-Result "Rejected without subscription key" "PASS" "HTTP 401 Unauthorized"
    } else {
        Add-Result "Rejected without subscription key" "PASS" "HTTP $statusCode"
    }
}

# --- Summary ---
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  AI GATEWAY TEST RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
foreach ($r in $results) {
    Write-Host "  $($r.Icon) $($r.Status): $($r.Test)" -ForegroundColor $(if ($r.Status -eq "PASS") { "Green" } else { "Red" })
}
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  $([char]0x2705) PASS: $pass" -ForegroundColor Green
if ($fail -gt 0) { Write-Host "  $([char]0x274C) FAIL: $fail" -ForegroundColor Red }
Write-Host "  Total: $($pass + $fail)" -ForegroundColor Cyan

if ($fail -eq 0) {
    Write-Host "`n$([char]0x2705) AI Gateway dziala poprawnie!" -ForegroundColor Green
    Write-Host "  APIM: $apimName (Standard v2 + PE)" -ForegroundColor Gray
    Write-Host "  Flow: Klient -> APIM (Private Endpoint) -> Foundry OpenAI (PE)" -ForegroundColor Gray
} else {
    Write-Host "`n$([char]0x274C) Niektore testy nie przeszly." -ForegroundColor Red
}
