<#
.SYNOPSIS
    Test BYO VNet configuration: subnets, delegations, NSG, DNS zones.
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "$PSScriptRoot\..\config\test-config.json"
)

$ErrorActionPreference = "Stop"
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$rg = $config.resource_group
$vnetName = $config.vnet.name

$results = @()
$pass = 0; $fail = 0; $warn = 0

function Add-Result($test, $status, $detail) {
    $icon = switch ($status) { "PASS" { [char]0x2705 } "FAIL" { [char]0x274C } "WARN" { [char]0x26A0 } }
    $script:results += [PSCustomObject]@{ Icon=$icon; Status=$status; Test=$test; Detail=$detail }
    switch ($status) { "PASS" { $script:pass++ } "FAIL" { $script:fail++ } "WARN" { $script:warn++ } }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  FAZA 2: NETWORK VALIDATION (BYO VNet)" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# --- 1. VNet existence ---
Write-Host "Checking VNet $vnetName..." -ForegroundColor Yellow
try {
    $vnet = az network vnet show --name $vnetName --resource-group $rg -o json 2>&1 | ConvertFrom-Json
    Add-Result "VNet: $vnetName" "PASS" "Address space: $($vnet.addressSpace.addressPrefixes -join ', ')"
} catch {
    Add-Result "VNet: $vnetName" "FAIL" "Not found in $rg"
}

# --- 2. Agent Subnet (delegated) ---
Write-Host "Checking Agent Subnet..." -ForegroundColor Yellow
$agentSubnet = $config.vnet.agent_subnet.name
try {
    $subnet = az network vnet subnet show --vnet-name $vnetName --name $agentSubnet --resource-group $rg -o json 2>&1 | ConvertFrom-Json
    Add-Result "Agent Subnet: $agentSubnet" "PASS" "CIDR: $($subnet.addressPrefix)"

    $delegations = $subnet.delegations | ForEach-Object { $_.serviceName }
    if ($delegations -contains "Microsoft.App/environments") {
        Add-Result "Agent Subnet Delegation" "PASS" "Microsoft.App/environments"
    } else {
        Add-Result "Agent Subnet Delegation" "FAIL" "Expected Microsoft.App/environments, got: $($delegations -join ', ')"
    }
} catch {
    Add-Result "Agent Subnet: $agentSubnet" "FAIL" "Not found"
}

# --- 3. PE Subnet (no delegation) ---
Write-Host "Checking PE Subnet..." -ForegroundColor Yellow
$peSubnet = $config.vnet.pe_subnet.name
try {
    $subnet = az network vnet subnet show --vnet-name $vnetName --name $peSubnet --resource-group $rg -o json 2>&1 | ConvertFrom-Json
    Add-Result "PE Subnet: $peSubnet" "PASS" "CIDR: $($subnet.addressPrefix)"

    if ($subnet.delegations.Count -eq 0) {
        Add-Result "PE Subnet No Delegation" "PASS" "No delegation (correct)"
    } else {
        Add-Result "PE Subnet No Delegation" "FAIL" "Has delegation: $($subnet.delegations[0].serviceName) — PE subnet must NOT have delegation"
    }
} catch {
    Add-Result "PE Subnet: $peSubnet" "FAIL" "Not found"
}

# --- 4. Bastion Subnet ---
Write-Host "Checking AzureBastionSubnet..." -ForegroundColor Yellow
try {
    $subnet = az network vnet subnet show --vnet-name $vnetName --name "AzureBastionSubnet" --resource-group $rg -o json 2>&1 | ConvertFrom-Json
    Add-Result "AzureBastionSubnet" "PASS" "CIDR: $($subnet.addressPrefix)"
} catch {
    Add-Result "AzureBastionSubnet" "WARN" "Not found (Bastion access won't work)"
}

# --- 5. GatewaySubnet ---
Write-Host "Checking GatewaySubnet..." -ForegroundColor Yellow
try {
    $subnet = az network vnet subnet show --vnet-name $vnetName --name "GatewaySubnet" --resource-group $rg -o json 2>&1 | ConvertFrom-Json
    Add-Result "GatewaySubnet" "PASS" "CIDR: $($subnet.addressPrefix)"
} catch {
    Add-Result "GatewaySubnet" "WARN" "Not found (VPN P2S won't work)"
}

# --- 6. Private DNS Zones linked to VNet ---
Write-Host "Checking Private DNS Zones..." -ForegroundColor Yellow
foreach ($zone in $config.dns_zones) {
    try {
        $links = az network private-dns link vnet list --zone-name $zone --resource-group $rg -o json 2>&1 | ConvertFrom-Json
        $linkedToVnet = $links | Where-Object { $_.virtualNetwork.id -like "*$vnetName*" }
        if ($linkedToVnet) {
            Add-Result "DNS Zone: $zone" "PASS" "Linked to $vnetName"
        } else {
            Add-Result "DNS Zone: $zone" "FAIL" "Exists but NOT linked to $vnetName"
        }
    } catch {
        Add-Result "DNS Zone: $zone" "FAIL" "Not found in $rg"
    }
}

# --- 7. Region consistency ---
Write-Host "Checking region consistency..." -ForegroundColor Yellow
$vnetLocation = $vnet.location
$expectedLocation = $config.location
if ($vnetLocation -eq $expectedLocation) {
    Add-Result "Region Consistency" "PASS" "VNet and config both in $expectedLocation"
} else {
    Add-Result "Region Consistency" "FAIL" "VNet in $vnetLocation, config expects $expectedLocation"
}

# --- Print results ---
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  NETWORK VALIDATION RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
foreach ($r in $results) {
    $color = switch ($r.Status) { "PASS" { "Green" } "FAIL" { "Red" } "WARN" { "Yellow" } }
    Write-Host "$($r.Icon) $($r.Status)  $($r.Test): $($r.Detail)" -ForegroundColor $color
}
Write-Host "`n--- Summary: $pass PASS, $fail FAIL, $warn WARN ---" -ForegroundColor Cyan

if ($fail -gt 0) { exit 1 } else { exit 0 }
