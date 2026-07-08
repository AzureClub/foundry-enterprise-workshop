<#
.SYNOPSIS
    Test native Foundry AI Gateway backed by APIM Standard v2 with Private Endpoint.
.DESCRIPTION
    Validates the portal-configured Foundry AI Gateway integration from inside the VNet.
    The script discovers the APIM instance dynamically from the resource group, checks
    private networking, sends a chat completion through the APIM gateway, and inspects
    Foundry REST payloads for AI Gateway configuration evidence.
.EXAMPLE
    .\15-test-foundry-ai-gateway.ps1
#>
param(
    [Parameter(Mandatory = $false)]
    [string]$ConfigPath = "$PSScriptRoot\..\config\test-config.json",

    [Parameter(Mandatory = $false)]
    [string]$ModelName = "gpt-4.1",

    [Parameter(Mandatory = $false)]
    [string]$ApiVersion = "2024-12-01-preview"
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $ConfigPath)) {
    throw "Config file not found: $ConfigPath"
}

$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rg = $config.resource_group
$subscriptionId = $config.subscription_id

if (-not $subscriptionId -or $subscriptionId -eq "YOUR-SUBSCRIPTION-ID") {
    $subscriptionId = (& az account show --query id -o tsv --only-show-errors 2>&1 | Out-String).Trim()
    if ($LASTEXITCODE -ne 0 -or -not $subscriptionId) {
        throw "Could not determine subscription ID from Azure CLI."
    }
}

if (-not $PSBoundParameters.ContainsKey("ModelName") -and $config.foundry.model_name) {
    $ModelName = [string]$config.foundry.model_name
}

$results = @()
$pass = 0
$fail = 0

function Add-Result {
    param(
        [string]$Test,
        [ValidateSet("PASS", "FAIL")]
        [string]$Status,
        [string]$Detail
    )

    $icon = if ($Status -eq "PASS") { [char]0x2705 } else { [char]0x274C }
    $script:results += [PSCustomObject]@{
        Icon   = $icon
        Status = $Status
        Test   = $Test
        Detail = $Detail
    }

    if ($Status -eq "PASS") {
        $script:pass++
        Write-Host "  $icon PASS: $Test" -ForegroundColor Green
    } else {
        $script:fail++
        Write-Host "  $icon FAIL: $Test" -ForegroundColor Red
    }

    if ($Detail) {
        Write-Host "     $Detail" -ForegroundColor Gray
    }
}

function Invoke-AzJson {
    param(
        [string[]]$Arguments,
        [string]$Description
    )

    $output = & az @Arguments --only-show-errors -o json 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed. $((($output | Out-String).Trim()))"
    }

    $text = ($output | Out-String).Trim()
    if (-not $text) {
        return $null
    }

    return $text | ConvertFrom-Json
}

function Invoke-AzTsv {
    param(
        [string[]]$Arguments,
        [string]$Description
    )

    $output = & az @Arguments --only-show-errors -o tsv 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed. $((($output | Out-String).Trim()))"
    }

    return (($output | Out-String).Trim())
}

function Test-PrivateIp {
    param([string]$IpAddress)

    if (-not $IpAddress) { return $false }
    return $IpAddress -match '^(10\.)' -or
           $IpAddress -match '^(192\.168\.)' -or
           $IpAddress -match '^(172\.(1[6-9]|2[0-9]|3[0-1])\.)'
}

function Convert-ToFlatString {
    param($Value)

    if ($null -eq $Value) { return "" }
    if ($Value -is [string]) { return $Value }
    if ($Value -is [ValueType]) { return [string]$Value }

    try {
        return ($Value | ConvertTo-Json -Depth 20 -Compress)
    } catch {
        return [string]$Value
    }
}

function Find-GatewayEvidence {
    param(
        $InputObject,
        [string]$Path,
        [string[]]$Hints
    )

    $matches = @()
    if ($null -eq $InputObject) {
        return $matches
    }

    if ($InputObject -is [string] -or $InputObject -is [ValueType]) {
        return $matches
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $index = 0
        foreach ($item in $InputObject) {
            $matches += Find-GatewayEvidence -InputObject $item -Path "$Path[$index]" -Hints $Hints
            $index++
        }
        return $matches
    }

    foreach ($property in $InputObject.PSObject.Properties) {
        $childPath = if ($Path) { "$Path.$($property.Name)" } else { $property.Name }
        $valueString = Convert-ToFlatString -Value $property.Value
        $nameHit = $property.Name -match '(?i)api.?management|apim|ai.?gateway|gateway'
        $valueHit = $false

        foreach ($hint in $Hints) {
            if ($hint -and $valueString -like "*$hint*") {
                $valueHit = $true
                break
            }
        }

        $enabledHit = ($property.Name -match '(?i)gatewaystatus|status') -and ($valueString -match '(?i)enabled')

        if ($nameHit -or $valueHit -or $enabledHit) {
            $preview = $valueString
            if ($preview.Length -gt 180) {
                $preview = $preview.Substring(0, 177) + "..."
            }

            $matches += [PSCustomObject]@{
                Path  = $childPath
                Value = $preview
            }
        }

        $matches += Find-GatewayEvidence -InputObject $property.Value -Path $childPath -Hints $Hints
    }

    return $matches
}

function Invoke-HttpJson {
    param(
        [string]$Method,
        [string]$Uri,
        [hashtable]$Headers,
        [string]$Body,
        [int]$TimeoutSeconds = 90
    )

    $handler = [System.Net.Http.HttpClientHandler]::new()
    $client = [System.Net.Http.HttpClient]::new($handler)
    $client.Timeout = [TimeSpan]::FromSeconds($TimeoutSeconds)

    try {
        $request = [System.Net.Http.HttpRequestMessage]::new(([System.Net.Http.HttpMethod]::new($Method)), $Uri)

        foreach ($headerName in $Headers.Keys) {
            if ($headerName -ne "Content-Type") {
                [void]$request.Headers.TryAddWithoutValidation($headerName, [string]$Headers[$headerName])
            }
        }

        if ($Body) {
            $contentType = if ($Headers.ContainsKey("Content-Type")) { $Headers["Content-Type"] } else { "application/json" }
            $request.Content = [System.Net.Http.StringContent]::new($Body, [System.Text.Encoding]::UTF8, $contentType)
        }

        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        $bodyText = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        $responseHeaders = @{}

        foreach ($header in $response.Headers) {
            $responseHeaders[$header.Key] = ($header.Value -join ", ")
        }
        foreach ($header in $response.Content.Headers) {
            $responseHeaders[$header.Key] = ($header.Value -join ", ")
        }

        $jsonBody = $null
        if ($bodyText) {
            try {
                $jsonBody = $bodyText | ConvertFrom-Json
            } catch {
            }
        }

        return [PSCustomObject]@{
            StatusCode        = [int]$response.StatusCode
            IsSuccessStatusCode = $response.IsSuccessStatusCode
            Headers           = $responseHeaders
            Body              = $bodyText
            Json              = $jsonBody
        }
    } finally {
        if ($client) { $client.Dispose() }
        if ($handler) { $handler.Dispose() }
    }
}

function Get-ApimAuthContext {
    param(
        [string]$SubscriptionId,
        [string]$ResourceGroup,
        [string]$ApimName
    )

    foreach ($subscriptionName in @("foundry-byom", "master")) {
        try {
            $secret = Invoke-AzJson -Arguments @(
                "rest", "--method", "post",
                "--url", "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroup/providers/Microsoft.ApiManagement/service/$ApimName/subscriptions/$subscriptionName/listSecrets?api-version=2024-06-01-preview"
            ) -Description "Retrieving APIM subscription secret '$subscriptionName'"

            if ($secret.primaryKey) {
                return [PSCustomObject]@{
                    Mode    = "Subscription key ($subscriptionName)"
                    Headers = @{
                        "Ocp-Apim-Subscription-Key" = [string]$secret.primaryKey
                        "Content-Type"              = "application/json"
                    }
                }
            }
        } catch {
        }
    }

    try {
        $token = Invoke-AzTsv -Arguments @(
            "account", "get-access-token",
            "--resource", "https://cognitiveservices.azure.com/",
            "--query", "accessToken"
        ) -Description "Retrieving AAD token for APIM gateway"

        if ($token) {
            return [PSCustomObject]@{
                Mode    = "AAD token"
                Headers = @{
                    "Authorization" = "Bearer $token"
                    "Content-Type"  = "application/json"
                }
            }
        }
    } catch {
    }

    throw "Could not acquire APIM authentication. Tried 'foundry-byom', 'master', and AAD token."
}

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "  FOUNDRY AI GATEWAY VALIDATION" -ForegroundColor Cyan
Write-Host "==================================================`n" -ForegroundColor Cyan
Write-Host "Resource group : $rg" -ForegroundColor DarkCyan
Write-Host "Config file    : $ConfigPath" -ForegroundColor DarkCyan
Write-Host "Model          : $ModelName" -ForegroundColor DarkCyan

$apimList = Invoke-AzJson -Arguments @("apim", "list", "--resource-group", $rg) -Description "Listing APIM instances"
$apimCandidates = @($apimList)
if (-not $apimCandidates -or $apimCandidates.Count -eq 0) {
    throw "No APIM instance found in resource group '$rg'."
}

$apimSummary = $apimCandidates | Where-Object { $_.sku.name -eq "StandardV2" } | Select-Object -First 1
if (-not $apimSummary) {
    $apimSummary = $apimCandidates | Select-Object -First 1
}

$apimName = $apimSummary.name
$apimDetails = Invoke-AzJson -Arguments @("apim", "show", "--name", $apimName, "--resource-group", $rg) -Description "Getting APIM details"
$apimResource = Invoke-AzJson -Arguments @("resource", "show", "--ids", $apimDetails.id, "--api-version", "2024-05-01") -Description "Getting APIM ARM resource"
$gatewayUrl = ([string]$apimDetails.gatewayUrl).TrimEnd("/")
$gatewayHost = ([System.Uri]$gatewayUrl).Host

Write-Host "`nDiscovered APIM : $apimName" -ForegroundColor Cyan
Write-Host "Gateway URL     : $gatewayUrl" -ForegroundColor Cyan
Write-Host "Gateway host    : $gatewayHost" -ForegroundColor Cyan

Write-Host "`n--- Test 1/8: APIM Discovery ---" -ForegroundColor Yellow
$skuName = [string]$apimDetails.sku.name
if ($skuName -eq "StandardV2") {
    Add-Result "APIM discovery" "PASS" "Found '$apimName' in $rg with SKU $skuName."
} else {
    Add-Result "APIM discovery" "FAIL" "Found '$apimName', but expected SKU StandardV2 and got '$skuName'."
}

Write-Host "`n--- Test 2/8: Gateway Status ---" -ForegroundColor Yellow
$provisioningState = [string]$apimResource.properties.provisioningState
if (-not $provisioningState) {
    $provisioningState = [string]$apimDetails.provisioningState
}

if ($provisioningState -eq "Succeeded" -and $gatewayUrl) {
    Add-Result "Gateway status" "PASS" "ProvisioningState=$provisioningState, GatewayUrl present."
} else {
    Add-Result "Gateway status" "FAIL" "ProvisioningState='$provisioningState', GatewayUrl='$gatewayUrl'."
}

Write-Host "`n--- Test 3/8: Private Endpoint ---" -ForegroundColor Yellow
$privateEndpoints = Invoke-AzJson -Arguments @("network", "private-endpoint", "list", "--resource-group", $rg) -Description "Listing private endpoints"
$apimPrivateEndpoint = $privateEndpoints | Where-Object {
    $matched = $false
    foreach ($connection in @($_.privateLinkServiceConnections)) {
        if ($connection.privateLinkServiceId -eq $apimDetails.id) {
            $matched = $true
            break
        }
    }
    $matched
} | Select-Object -First 1

$privateEndpointStatus = $null
$privateEndpointIp = $null

if (-not $apimPrivateEndpoint -and $apimResource.properties.privateEndpointConnections) {
    $approvedConnection = @($apimResource.properties.privateEndpointConnections | Where-Object {
        $_.properties.privateLinkServiceConnectionState.status -eq "Approved"
    }) | Select-Object -First 1

    if ($approvedConnection) {
        $privateEndpointStatus = $approvedConnection.properties.privateLinkServiceConnectionState.status
    }
}

if ($apimPrivateEndpoint) {
    $primaryConnection = @($apimPrivateEndpoint.privateLinkServiceConnections)[0]
    if ($primaryConnection.privateLinkServiceConnectionState.status) {
        $privateEndpointStatus = [string]$primaryConnection.privateLinkServiceConnectionState.status
    }

    $nicId = $null
    if ($apimPrivateEndpoint.customNetworkInterface -and $apimPrivateEndpoint.customNetworkInterface.id) {
        $nicId = $apimPrivateEndpoint.customNetworkInterface.id
    } elseif ($apimPrivateEndpoint.networkInterfaces -and $apimPrivateEndpoint.networkInterfaces[0].id) {
        $nicId = $apimPrivateEndpoint.networkInterfaces[0].id
    }

    if ($nicId) {
        $nic = Invoke-AzJson -Arguments @("network", "nic", "show", "--ids", $nicId) -Description "Getting private endpoint NIC"
        $privateEndpointIp = @($nic.ipConfigurations)[0].privateIPAddress
    }
}

if ($apimPrivateEndpoint -and $privateEndpointStatus -eq "Approved") {
    $detail = "Private endpoint '$($apimPrivateEndpoint.name)' is Approved"
    if ($privateEndpointIp) {
        $detail += " (IP: $privateEndpointIp)"
    }
    Add-Result "Private endpoint" "PASS" $detail
} elseif ($privateEndpointStatus -eq "Approved") {
    Add-Result "Private endpoint" "PASS" "APIM has an Approved private endpoint connection."
} else {
    Add-Result "Private endpoint" "FAIL" "No Approved APIM private endpoint found in '$rg'."
}

Write-Host "`n--- Test 4/8: DNS Resolution ---" -ForegroundColor Yellow
try {
    $dnsRecords = Resolve-DnsName -Name $gatewayHost -ErrorAction Stop
    $resolvedIps = @($dnsRecords | Where-Object { $_.QueryType -eq "A" } | ForEach-Object { $_.IPAddress })
    $privateResolvedIp = $resolvedIps | Where-Object { Test-PrivateIp $_ } | Select-Object -First 1

    if ($privateResolvedIp) {
        $detail = "$gatewayHost resolved to private IP $privateResolvedIp"
        if ($privateEndpointIp) {
            if ($privateResolvedIp -eq $privateEndpointIp) {
                $detail += " (matches PE NIC)"
            } else {
                $detail += " (PE NIC IP: $privateEndpointIp)"
            }
        }
        Add-Result "DNS resolution" "PASS" $detail
    } else {
        Add-Result "DNS resolution" "FAIL" "$gatewayHost did not resolve to a private RFC1918 address. Resolved: $($resolvedIps -join ', ')"
    }
} catch {
    Add-Result "DNS resolution" "FAIL" "Could not resolve $gatewayHost. Run this script from inside the VNet jumpbox."
}

Write-Host "`n--- Test 5/8: TCP Connectivity ---" -ForegroundColor Yellow
$tcpTarget = if ($privateEndpointIp) { $privateEndpointIp } else { $gatewayHost }
try {
    $tcp = Test-NetConnection -ComputerName $tcpTarget -Port 443 -WarningAction SilentlyContinue
    if ($tcp.TcpTestSucceeded) {
        Add-Result "TCP connectivity" "PASS" "TCP 443 reachable on $tcpTarget."
    } else {
        Add-Result "TCP connectivity" "FAIL" "TCP 443 is not reachable on $tcpTarget."
    }
} catch {
    Add-Result "TCP connectivity" "FAIL" $_.Exception.Message
}

Write-Host "`n--- Test 6/8: Chat Completions ---" -ForegroundColor Yellow
$authContext = $null
$chatResponse = $null

try {
    $authContext = Get-ApimAuthContext -SubscriptionId $subscriptionId -ResourceGroup $rg -ApimName $apimName
    Write-Host "Using auth mode  : $($authContext.Mode)" -ForegroundColor DarkCyan

    $chatUrl = "$gatewayUrl/openai/deployments/$ModelName/chat/completions?api-version=$ApiVersion"
    $chatBody = @{
        messages = @(
            @{ role = "system"; content = "You are a helpful assistant. Reply in one short sentence." },
            @{ role = "user"; content = "Confirm that the request went through the gateway." }
        )
        temperature = 0
        max_tokens  = 80
    } | ConvertTo-Json -Depth 6 -Compress

    $start = Get-Date
    $chatResponse = Invoke-HttpJson -Method "POST" -Uri $chatUrl -Headers $authContext.Headers -Body $chatBody -TimeoutSeconds 120
    $elapsedMs = [int](((Get-Date) - $start).TotalMilliseconds)

    if ($chatResponse.IsSuccessStatusCode -and $chatResponse.Json -and $chatResponse.Json.choices) {
        $answer = [string]$chatResponse.Json.choices[0].message.content
        $usedModel = [string]$chatResponse.Json.model
        $totalTokens = $chatResponse.Json.usage.total_tokens
        $detail = "HTTP $($chatResponse.StatusCode), auth=$($authContext.Mode), model=$usedModel, tokens=$totalTokens, latency=${elapsedMs}ms"
        Add-Result "Chat completions" "PASS" $detail
        if ($answer) {
            Write-Host "Response        : $answer" -ForegroundColor White
        }
    } else {
        $bodyPreview = [string]$chatResponse.Body
        if (-not $bodyPreview) {
            $bodyPreview = "Empty response body."
        }
        if ($bodyPreview.Length -gt 220) {
            $bodyPreview = $bodyPreview.Substring(0, 217) + "..."
        }
        Add-Result "Chat completions" "FAIL" "HTTP $($chatResponse.StatusCode). $bodyPreview"
    }
} catch {
    Add-Result "Chat completions" "FAIL" $_.Exception.Message
}

Write-Host "`n--- Test 7/8: Token Metrics ---" -ForegroundColor Yellow
if ($chatResponse) {
    $tokenMetricHeaders = @($chatResponse.Headers.Keys | Where-Object { $_ -match '(?i)^x-ratelimit-.*tokens' })
    if ($tokenMetricHeaders.Count -gt 0) {
        $headerSummary = $tokenMetricHeaders | ForEach-Object { "$_=$($chatResponse.Headers[$_])" }
        Add-Result "Token metrics headers" "PASS" ($headerSummary -join "; ")
    } else {
        Add-Result "Token metrics headers" "FAIL" "No token-related x-ratelimit headers were returned."
    }
} else {
    Add-Result "Token metrics headers" "FAIL" "Chat completion request did not return a response to inspect."
}

Write-Host "`n--- Test 8/8: Foundry AI Gateway Config ---" -ForegroundColor Yellow
try {
    $foundryAccounts = Invoke-AzJson -Arguments @("cognitiveservices", "account", "list", "--resource-group", $rg) -Description "Listing Foundry accounts"
    $foundryAccount = $null

    if ($config.foundry.account_name) {
        $foundryAccount = @($foundryAccounts | Where-Object { $_.name -eq $config.foundry.account_name }) | Select-Object -First 1
    }
    if (-not $foundryAccount) {
        $foundryAccount = @($foundryAccounts | Where-Object { $_.kind -eq "AIServices" }) | Select-Object -First 1
    }
    if (-not $foundryAccount) {
        $foundryAccount = @($foundryAccounts)[0]
    }
    if (-not $foundryAccount) {
        throw "No Foundry account discovered in $rg."
    }

    $accountName = $foundryAccount.name
    $accountResource = Invoke-AzJson -Arguments @(
        "rest", "--method", "get",
        "--url", "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$accountName?api-version=2025-04-01-preview"
    ) -Description "Getting Foundry account resource"

    $projectPayload = $null
    try {
        $projectPayload = Invoke-AzJson -Arguments @(
            "rest", "--method", "get",
            "--url", "https://management.azure.com/subscriptions/$subscriptionId/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$accountName/projects?api-version=2025-04-01-preview"
        ) -Description "Listing Foundry projects"
    } catch {
    }

    $hints = @($apimName, $apimDetails.id, $gatewayUrl, $gatewayHost)
    $evidence = @()
    $evidence += Find-GatewayEvidence -InputObject $accountResource -Path "account" -Hints $hints
    if ($projectPayload) {
        $evidence += Find-GatewayEvidence -InputObject $projectPayload -Path "projects" -Hints $hints
    }

    $strongEvidence = $evidence | Where-Object {
        $_.Path -match '(?i)api.?management|apim|ai.?gateway|gateway' -or
        $_.Value -like "*$apimName*" -or
        $_.Value -like "*$gatewayUrl*" -or
        $_.Value -like "*$gatewayHost*" -or
        $_.Value -like "*Enabled*"
    } | Select-Object -First 5

    if ($strongEvidence -and $strongEvidence.Count -gt 0) {
        $detail = ($strongEvidence | ForEach-Object { "$($_.Path)=$($_.Value)" }) -join " | "
        Add-Result "Foundry AI Gateway config" "PASS" "Account '$accountName' shows gateway evidence: $detail"
    } else {
        Add-Result "Foundry AI Gateway config" "FAIL" "No AI Gateway-related configuration evidence found in Foundry account/project REST payloads for '$accountName'."
    }
} catch {
    Add-Result "Foundry AI Gateway config" "FAIL" $_.Exception.Message
}

Write-Host "`n==================================================" -ForegroundColor Cyan
Write-Host "  FOUNDRY AI GATEWAY TEST RESULTS" -ForegroundColor Cyan
Write-Host "==================================================" -ForegroundColor Cyan
$results | Format-Table Icon, Status, Test, Detail -AutoSize
Write-Host "PASS : $pass" -ForegroundColor Green
Write-Host "FAIL : $fail" -ForegroundColor $(if ($fail -gt 0) { "Red" } else { "Green" })
Write-Host "TOTAL: $($pass + $fail)" -ForegroundColor Cyan

if ($fail -eq 0) {
    Write-Host "`n$([char]0x2705) Native Foundry AI Gateway is reachable and correctly configured." -ForegroundColor Green
    exit 0
}

Write-Host "`n$([char]0x274C) One or more Foundry AI Gateway checks failed." -ForegroundColor Red
exit 1
