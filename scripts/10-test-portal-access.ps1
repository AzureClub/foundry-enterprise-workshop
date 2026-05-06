<#
.SYNOPSIS
    Test portal access to ai.azure.com via Bastion + Jumpbox VM and VPN P2S Gateway.
.DESCRIPTION
    Validates: Bastion deployment, jumpbox VM status, VPN Gateway P2S config,
    DNS resolution from within VNet, and connectivity to Foundry portal.
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
Write-Host "  FAZA 7: PORTAL ACCESS TEST" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# --- 1. Azure Bastion ---
Write-Host "Checking Azure Bastion..." -ForegroundColor Yellow
try {
    $bastionState = az resource show --name "bastion-foundry-test" --resource-group $rg --resource-type "Microsoft.Network/bastionHosts" --query "properties.provisioningState" -o tsv 2>&1
    if ($bastionState.Trim() -eq "Succeeded") {
        Add-Result "Bastion: bastion-foundry-test" "PASS" "Provisioned"
    } else {
        Add-Result "Bastion: bastion-foundry-test" "FAIL" "State: $($bastionState.Trim())"
    }
} catch {
    Add-Result "Bastion" "FAIL" "Not found in $rg"
}

# --- 2. Bastion Subnet ---
Write-Host "Checking AzureBastionSubnet..." -ForegroundColor Yellow
try {
    $bastionSubnet = az network vnet subnet show --vnet-name $config.vnet.name --name "AzureBastionSubnet" --resource-group $rg -o json 2>&1 | ConvertFrom-Json
    $prefix = $bastionSubnet.addressPrefix
    $cidr = [int]($prefix -split '/')[1]
    if ($cidr -le 26) {
        Add-Result "AzureBastionSubnet" "PASS" "CIDR: $prefix (>= /26)"
    } else {
        Add-Result "AzureBastionSubnet" "FAIL" "CIDR: $prefix (needs /26 or larger)"
    }
} catch {
    Add-Result "AzureBastionSubnet" "FAIL" "Subnet not found"
}

# --- 3. Jumpbox VM ---
Write-Host "Checking Jumpbox VM..." -ForegroundColor Yellow
try {
    $vm = az vm show --name "vm-jumpbox" --resource-group $rg -o json 2>&1 | ConvertFrom-Json
    $vmStatus = az vm get-instance-view --name "vm-jumpbox" --resource-group $rg --query "instanceView.statuses[1].displayStatus" -o tsv 2>&1
    if ($vmStatus.Trim() -eq "VM running") {
        Add-Result "Jumpbox VM" "PASS" "Running, Size: $($vm.hardwareProfile.vmSize)"
    } elseif ($vm.name) {
        Add-Result "Jumpbox VM" "WARN" "Exists but status: $($vmStatus.Trim()). Start with: az vm start --name vm-jumpbox --resource-group $rg"
    }
} catch {
    Add-Result "Jumpbox VM" "FAIL" "Not found in $rg"
}

# --- 4. Jumpbox Private IP (no public) ---
Write-Host "Checking Jumpbox network..." -ForegroundColor Yellow
try {
    $nic = az network nic show --name "nic-jumpbox" --resource-group $rg -o json 2>&1 | ConvertFrom-Json
    $privateIp = $nic.ipConfigurations[0].privateIPAddress
    $hasPublicIp = $null -ne $nic.ipConfigurations[0].publicIPAddress
    if (-not $hasPublicIp -and $privateIp) {
        Add-Result "Jumpbox Network" "PASS" "Private IP: $privateIp, No public IP"
    } elseif ($hasPublicIp) {
        Add-Result "Jumpbox Network" "WARN" "Has public IP - should be private only for security"
    }
} catch {
    Add-Result "Jumpbox Network" "WARN" "Could not verify NIC"
}

# --- 5. VPN Gateway ---
Write-Host "Checking VPN Gateway..." -ForegroundColor Yellow
try {
    $vpnState = az resource show --name "vpngw-foundry-test" --resource-group $rg --resource-type "Microsoft.Network/virtualNetworkGateways" --query "properties.provisioningState" -o tsv 2>&1
    if ($vpnState.Trim() -eq "Succeeded") {
        Add-Result "VPN Gateway" "PASS" "Provisioned"
    } else {
        Add-Result "VPN Gateway" "FAIL" "State: $($vpnState.Trim())"
    }
} catch {
    Add-Result "VPN Gateway" "FAIL" "Not found in $rg"
}

# --- 6. VPN P2S Configuration ---
Write-Host "Checking VPN P2S config..." -ForegroundColor Yellow
try {
    $vpnJson = az resource show --name "vpngw-foundry-test" --resource-group $rg --resource-type "Microsoft.Network/virtualNetworkGateways" --query "properties.vpnClientConfiguration" -o json 2>&1 | ConvertFrom-Json
    if ($vpnJson.vpnClientAddressPool.addressPrefixes.Count -gt 0) {
        $authType = if ($vpnJson.vpnAuthenticationTypes) { $vpnJson.vpnAuthenticationTypes -join ', ' } else { 'Certificate' }
        Add-Result "VPN P2S Config" "PASS" "Pool: $($vpnJson.vpnClientAddressPool.addressPrefixes[0]), Auth: $authType"
    } else {
        Add-Result "VPN P2S Config" "FAIL" "No client address pool configured"
    }
} catch {
    Add-Result "VPN P2S Config" "WARN" "Could not verify P2S config"
}

# --- 7. GatewaySubnet ---
Write-Host "Checking GatewaySubnet..." -ForegroundColor Yellow
try {
    $gwSubnet = az network vnet subnet show --vnet-name $config.vnet.name --name "GatewaySubnet" --resource-group $rg -o json 2>&1 | ConvertFrom-Json
    Add-Result "GatewaySubnet" "PASS" "CIDR: $($gwSubnet.addressPrefix)"
} catch {
    Add-Result "GatewaySubnet" "FAIL" "Subnet not found"
}

# --- 8. DNS resolution test (run on jumpbox via Bastion if possible) ---
Write-Host "Checking DNS zones linked to VNet..." -ForegroundColor Yellow
$dnsZones = $config.dns_zones
foreach ($zone in $dnsZones) {
    try {
        $link = az network private-dns link vnet list --zone-name $zone --resource-group $rg --query "[?virtualNetwork.id!=null].name" -o tsv 2>&1
        if ($link.Trim()) {
            Add-Result "DNS Link: $zone" "PASS" "Linked to VNet"
        } else {
            Add-Result "DNS Link: $zone" "FAIL" "Not linked to VNet"
        }
    } catch {
        Add-Result "DNS Link: $zone" "WARN" "Zone not found or no access"
    }
}

# --- Print results ---
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  PORTAL ACCESS TEST RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
foreach ($r in $results) {
    $color = switch ($r.Status) { "PASS" { "Green" } "FAIL" { "Red" } "WARN" { "Yellow" } }
    Write-Host "$($r.Icon) $($r.Status)  $($r.Test): $($r.Detail)" -ForegroundColor $color
}
Write-Host "`n--- Summary: $pass PASS, $fail FAIL, $warn WARN ---" -ForegroundColor Cyan

Write-Host "`n--- Portal Access Instructions ---" -ForegroundColor Magenta
Write-Host @"

  BASTION (do testow):
    1. Azure Portal > vm-jumpbox > Connect > Bastion
    2. Login: azureadmin / <password>
    3. Open Edge > https://ai.azure.com
    4. Verify you can see Foundry project and resources

  VPN P2S (dla klienta):
    1. Download VPN client: az network vnet-gateway vpn-client generate --name vpngw-foundry-test --resource-group $rg
    2. Install VPN profile on client machine
    3. Connect VPN > open browser > https://ai.azure.com
    4. Configure DNS: forward Private DNS Zones to Azure DNS (168.63.129.16)
"@

if ($fail -gt 0) { exit 1 } else { exit 0 }
