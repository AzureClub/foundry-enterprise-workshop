<#
.SYNOPSIS
    Test Private Endpoints: status, DNS resolution, public access disabled.
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
Write-Host "  FAZA 3: PRIVATE ENDPOINTS VALIDATION" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# --- 1. List all Private Endpoints in RG ---
Write-Host "Listing Private Endpoints in $rg..." -ForegroundColor Yellow
$peList = az network private-endpoint list --resource-group $rg -o json 2>&1 | ConvertFrom-Json

if ($peList.Count -eq 0) {
    Add-Result "Private Endpoints" "FAIL" "No PE found in $rg"
} else {
    Add-Result "Private Endpoints Count" "PASS" "$($peList.Count) PE(s) found"
}

# --- 2. Check each PE status ---
foreach ($pe in $peList) {
    $peName = $pe.name
    Write-Host "Checking PE: $peName..." -ForegroundColor Yellow

    # Connection status
    $connections = $pe.privateLinkServiceConnections + $pe.manualPrivateLinkServiceConnections
    foreach ($conn in $connections) {
        $status = $conn.privateLinkServiceConnectionState.status
        $groupIds = $conn.groupIds -join ', '
        if ($status -eq "Approved") {
            Add-Result "PE $peName ($groupIds)" "PASS" "Status: Approved"
        } else {
            Add-Result "PE $peName ($groupIds)" "FAIL" "Status: $status (expected Approved)"
        }
    }

    # NIC / Private IP
    if ($pe.networkInterfaces.Count -gt 0) {
        $nicId = $pe.networkInterfaces[0].id
        $nicName = ($nicId -split '/')[-1]
        try {
            $nic = az network nic show --ids $nicId -o json 2>&1 | ConvertFrom-Json
            $privateIp = $nic.ipConfigurations[0].privateIPAddress
            Add-Result "PE $peName IP" "PASS" "Private IP: $privateIp"
        } catch {
            Add-Result "PE $peName IP" "WARN" "Could not read NIC"
        }
    }
}

# --- 3. Check public network access on resources ---
Write-Host "`nChecking public network access..." -ForegroundColor Yellow

# Foundry / Cognitive Services
$aiAccounts = az cognitiveservices account list --resource-group $rg -o json 2>&1 | ConvertFrom-Json
foreach ($ai in $aiAccounts) {
    $publicAccess = $ai.properties.publicNetworkAccess
    if ($publicAccess -eq "Disabled") {
        Add-Result "Public Access: $($ai.name)" "PASS" "Disabled"
    } else {
        Add-Result "Public Access: $($ai.name)" "FAIL" "Public access: $publicAccess (should be Disabled)"
    }
}

# Storage
$storageAccounts = az storage account list --resource-group $rg -o json 2>&1 | ConvertFrom-Json
foreach ($sa in $storageAccounts) {
    $publicAccess = $sa.publicNetworkAccess
    $sharedKey = $sa.allowSharedKeyAccess
    if ($publicAccess -eq "Disabled") {
        Add-Result "Public Access: $($sa.name)" "PASS" "Disabled"
    } else {
        Add-Result "Public Access: $($sa.name)" "FAIL" "Public access: $publicAccess"
    }
    if ($sharedKey -eq $false) {
        Add-Result "SharedKey: $($sa.name)" "PASS" "SharedKey disabled (AAD only)"
    } else {
        Add-Result "SharedKey: $($sa.name)" "WARN" "SharedKey enabled — best practice: disable"
    }
}

# AI Search
$searchServices = az search service list --resource-group $rg -o json 2>&1 | ConvertFrom-Json
foreach ($s in $searchServices) {
    $publicAccess = $s.publicNetworkAccess
    if ($publicAccess -eq "disabled") {
        Add-Result "Public Access: $($s.name)" "PASS" "Disabled"
    } else {
        Add-Result "Public Access: $($s.name)" "FAIL" "Public access: $publicAccess"
    }
}

# CosmosDB
$cosmosAccounts = az cosmosdb list --resource-group $rg -o json 2>&1 | ConvertFrom-Json
foreach ($c in $cosmosAccounts) {
    $publicAccess = $c.publicNetworkAccess
    $localAuth = $c.disableLocalAuth
    if ($publicAccess -eq "Disabled") {
        Add-Result "Public Access: $($c.name)" "PASS" "Disabled"
    } else {
        Add-Result "Public Access: $($c.name)" "FAIL" "Public access: $publicAccess"
    }
    if ($localAuth -eq $true) {
        Add-Result "Local Auth: $($c.name)" "PASS" "Local auth disabled (AAD only)"
    } else {
        Add-Result "Local Auth: $($c.name)" "WARN" "Local auth enabled — best practice: disable"
    }
}

# --- 4. DNS Zone records ---
Write-Host "`nChecking DNS A-records in Private DNS Zones..." -ForegroundColor Yellow
$dnsZones = $config.dns_zones | Where-Object { $_ -ne "privatelink.azure-api.net" }
foreach ($zone in $dnsZones) {
    try {
        $records = az network private-dns record-set a list --zone-name $zone --resource-group $rg -o json 2>&1 | ConvertFrom-Json
        if ($records.Count -gt 0) {
            foreach ($r in $records) {
                $ips = ($r.aRecords | ForEach-Object { $_.ipv4Address }) -join ', '
                Add-Result "DNS A: $($r.fqdn)" "PASS" "IPs: $ips"
            }
        } else {
            Add-Result "DNS Zone: $zone" "WARN" "No A records found"
        }
    } catch {
        Add-Result "DNS Zone: $zone" "WARN" "Could not query records"
    }
}

# --- Print results ---
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  PRIVATE ENDPOINTS VALIDATION RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
foreach ($r in $results) {
    $color = switch ($r.Status) { "PASS" { "Green" } "FAIL" { "Red" } "WARN" { "Yellow" } }
    Write-Host "$($r.Icon) $($r.Status)  $($r.Test): $($r.Detail)" -ForegroundColor $color
}
Write-Host "`n--- Summary: $pass PASS, $fail FAIL, $warn WARN ---" -ForegroundColor Cyan

if ($fail -gt 0) { exit 1 } else { exit 0 }
