<#
.SYNOPSIS
    End-to-end test report: aggregates all test results into a final GO/NO-GO report.
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "$PSScriptRoot\..\config\test-config.json",
    [Parameter(Mandatory=$false)]
    [string]$ReportPath = "$PSScriptRoot\..\report.txt"
)

$ErrorActionPreference = "Stop"
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rg = $config.resource_group
$location = $config.location

$allResults = @()
$totalPass = 0; $totalFail = 0; $totalWarn = 0

function Add-Result($phase, $test, $status, $detail) {
    $icon = switch ($status) { "PASS" { [char]0x2705 } "FAIL" { [char]0x274C } "WARN" { [char]0x26A0 } }
    $script:allResults += [PSCustomObject]@{ Phase=$phase; Icon=$icon; Status=$status; Test=$test; Detail=$detail }
    switch ($status) { "PASS" { $script:totalPass++ } "FAIL" { $script:totalFail++ } "WARN" { $script:totalWarn++ } }
}

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Write-Host "`n" -NoNewline
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "  FOUNDRY BYO VNet - END-TO-END TEST REPORT" -ForegroundColor Cyan
Write-Host "  Subscription: $($config.subscription_id)" -ForegroundColor Gray
Write-Host "  Resource Group: $rg" -ForegroundColor Gray
Write-Host "  Region: $location" -ForegroundColor Gray
Write-Host "  Timestamp: $timestamp" -ForegroundColor Gray
Write-Host ("=" * 60) -ForegroundColor Cyan

# ========== NETWORK ==========
Write-Host "`n--- NETWORK ---" -ForegroundColor Magenta
try {
    $vnet = az network vnet show --name $config.vnet.name --resource-group $rg -o json 2>&1 | ConvertFrom-Json
    Add-Result "Network" "VNet exists" "PASS" $config.vnet.name

    $agentSubnet = az network vnet subnet show --vnet-name $config.vnet.name --name $config.vnet.agent_subnet.name --resource-group $rg -o json 2>&1 | ConvertFrom-Json
    $hasDelegation = ($agentSubnet.delegations | Where-Object { $_.serviceName -eq "Microsoft.App/environments" }).Count -gt 0
    Add-Result "Network" "Agent subnet delegation" $(if($hasDelegation){"PASS"}else{"FAIL"}) "Microsoft.App/environments"

    $peSubnet = az network vnet subnet show --vnet-name $config.vnet.name --name $config.vnet.pe_subnet.name --resource-group $rg -o json 2>&1 | ConvertFrom-Json
    Add-Result "Network" "PE subnet (no delegation)" $(if($peSubnet.delegations.Count -eq 0){"PASS"}else{"FAIL"}) "$($peSubnet.addressPrefix)"
} catch {
    Add-Result "Network" "VNet check" "FAIL" $_.Exception.Message
}

# ========== PRIVATE ENDPOINTS ==========
Write-Host "`n--- PRIVATE ENDPOINTS ---" -ForegroundColor Magenta
$peList = az network private-endpoint list --resource-group $rg -o json 2>&1 | ConvertFrom-Json
Add-Result "PE" "Total PE count" $(if($peList.Count -ge 4){"PASS"}else{"FAIL"}) "$($peList.Count) PE(s)"
foreach ($pe in $peList) {
    $conn = ($pe.privateLinkServiceConnections + $pe.manualPrivateLinkServiceConnections) | Select-Object -First 1
    $status = $conn.privateLinkServiceConnectionState.status
    Add-Result "PE" $pe.name $(if($status -eq "Approved"){"PASS"}else{"FAIL"}) "Status: $status"
}

# ========== DNS ZONES ==========
Write-Host "`n--- DNS ZONES ---" -ForegroundColor Magenta
foreach ($zone in ($config.dns_zones | Where-Object { $_ -ne "privatelink.azure-api.net" })) {
    try {
        $links = az network private-dns link vnet list --zone-name $zone --resource-group $rg -o json 2>&1 | ConvertFrom-Json
        $linked = ($links | Where-Object { $_.virtualNetwork.id -like "*$($config.vnet.name)*" }).Count -gt 0
        Add-Result "DNS" $zone $(if($linked){"PASS"}else{"FAIL"}) $(if($linked){"Linked"}else{"NOT linked"})
    } catch {
        Add-Result "DNS" $zone "FAIL" "Zone not found"
    }
}

# ========== FOUNDRY ==========
Write-Host "`n--- FOUNDRY ACCOUNT ---" -ForegroundColor Magenta
$aiAccounts = az cognitiveservices account list --resource-group $rg -o json 2>&1 | ConvertFrom-Json
$mainAccount = $aiAccounts | Where-Object { $_.kind -eq "AIServices" } | Select-Object -First 1
if ($mainAccount) {
    Add-Result "Foundry" "Account exists" "PASS" $mainAccount.name
    Add-Result "Foundry" "Public access" $(if($mainAccount.properties.publicNetworkAccess -eq "Disabled"){"PASS"}else{"FAIL"}) $mainAccount.properties.publicNetworkAccess
    $hasMI = $mainAccount.identity.type -match "SystemAssigned"
    Add-Result "Foundry" "System MI" $(if($hasMI){"PASS"}else{"FAIL"}) $mainAccount.identity.type
    $hasNetInjection = ($mainAccount.properties.networkInjections | Where-Object { $_.scenario -eq "agent" }).Count -gt 0
    Add-Result "Foundry" "Network injection (BYO VNet)" $(if($hasNetInjection){"PASS"}else{"FAIL"}) "scenario: agent"
} else {
    Add-Result "Foundry" "Account" "FAIL" "No AIServices account found"
}

# ========== PORTAL ACCESS ==========
Write-Host "`n--- PORTAL ACCESS ---" -ForegroundColor Magenta
try {
    $bastion = az resource show --name "bastion-foundry-test" --resource-group $rg --resource-type "Microsoft.Network/bastionHosts" --query "properties.provisioningState" -o tsv 2>&1
    Add-Result "Portal" "Bastion" $(if($bastion.Trim() -eq "Succeeded"){"PASS"}else{"FAIL"}) $bastion.Trim()
} catch {
    Add-Result "Portal" "Bastion" "WARN" "Not deployed"
}

try {
    $vmStatus = az vm get-instance-view --name "vm-jumpbox" --resource-group $rg --query "instanceView.statuses[1].displayStatus" -o tsv 2>&1
    Add-Result "Portal" "Jumpbox VM" $(if($vmStatus.Trim() -eq "VM running"){"PASS"}else{"WARN"}) $vmStatus.Trim()
} catch {
    Add-Result "Portal" "Jumpbox VM" "WARN" "Not deployed"
}

try {
    $vpnState = az resource show --name "vpngw-foundry-test" --resource-group $rg --resource-type "Microsoft.Network/virtualNetworkGateways" --query "properties.provisioningState" -o tsv 2>&1
    Add-Result "Portal" "VPN Gateway" $(if($vpnState.Trim() -eq "Succeeded"){"PASS"}else{"FAIL"}) $vpnState.Trim()
} catch {
    Add-Result "Portal" "VPN Gateway" "WARN" "Not deployed"
}

# ========== RBAC ==========
Write-Host "`n--- RBAC ---" -ForegroundColor Magenta
if ($mainAccount -and $mainAccount.identity.principalId) {
    $roles = az role assignment list --assignee $mainAccount.identity.principalId --resource-group $rg -o json 2>&1 | ConvertFrom-Json
    Add-Result "RBAC" "Account MI role count" $(if($roles.Count -ge 3){"PASS"}else{"WARN"}) "$($roles.Count) role(s)"
}

# ========== FINAL VERDICT ==========
Write-Host "`n" -NoNewline
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "  FINAL REPORT" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan

foreach ($r in $allResults) {
    $color = switch ($r.Status) { "PASS" { "Green" } "FAIL" { "Red" } "WARN" { "Yellow" } }
    Write-Host "$($r.Icon) $($r.Status)  [$($r.Phase)] $($r.Test): $($r.Detail)" -ForegroundColor $color
}

Write-Host "`n" -NoNewline
Write-Host ("=" * 60) -ForegroundColor Cyan
$verdict = if ($totalFail -eq 0) { "GO" } else { "NO-GO" }
$verdictColor = if ($totalFail -eq 0) { "Green" } else { "Red" }
Write-Host "  VERDICT: $verdict" -ForegroundColor $verdictColor
Write-Host "  Total: $totalPass PASS | $totalFail FAIL | $totalWarn WARN" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan

# Save report to file
$reportContent = @"
FOUNDRY BYO VNet - E2E TEST REPORT
===================================
Subscription: $($config.subscription_id)
Resource Group: $rg
Region: $location
Timestamp: $timestamp

RESULTS:
$($allResults | ForEach-Object { "$($_.Icon) $($_.Status)  [$($_.Phase)] $($_.Test): $($_.Detail)" } | Out-String)

VERDICT: $verdict
Total: $totalPass PASS | $totalFail FAIL | $totalWarn WARN
"@

$reportContent | Out-File -FilePath $ReportPath -Encoding utf8 -Force
Write-Host "`nReport saved to: $ReportPath" -ForegroundColor Gray

if ($totalFail -gt 0) { exit 1 } else { exit 0 }
