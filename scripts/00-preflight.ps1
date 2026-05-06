<#
.SYNOPSIS
    Pre-flight checks for Foundry BYO VNet deployment.
.DESCRIPTION
    Validates: az CLI login, subscription, provider registration, permissions, region.
    Run this BEFORE deploying any Bicep templates.
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$ConfigPath = "$PSScriptRoot\..\config\test-config.json"
)

$ErrorActionPreference = "Stop"

# --- Load config ---
$config = Get-Content $ConfigPath -Raw | ConvertFrom-Json
$subscriptionId = $config.subscription_id
$location = $config.location
$providers = $config.required_providers

$results = @()
$pass = 0; $fail = 0; $warn = 0

function Add-Result($test, $status, $detail) {
    $icon = switch ($status) { "PASS" { [char]0x2705 } "FAIL" { [char]0x274C } "WARN" { [char]0x26A0  } }
    $script:results += [PSCustomObject]@{ Icon=$icon; Status=$status; Test=$test; Detail=$detail }
    switch ($status) { "PASS" { $script:pass++ } "FAIL" { $script:fail++ } "WARN" { $script:warn++ } }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  FAZA 0: PRE-FLIGHT CHECKS" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# --- 1. Az CLI login ---
Write-Host "Checking az CLI login..." -ForegroundColor Yellow
try {
    $account = az account show -o json 2>&1 | ConvertFrom-Json
    if ($account.id) {
        Add-Result "Az CLI login" "PASS" "Logged in as: $($account.user.name)"
    } else {
        Add-Result "Az CLI login" "FAIL" "Not logged in. Run: az login"
    }
} catch {
    Add-Result "Az CLI login" "FAIL" "az CLI not installed or not logged in"
}

# --- 2. Subscription ---
Write-Host "Setting subscription $subscriptionId..." -ForegroundColor Yellow
try {
    az account set --subscription $subscriptionId 2>&1 | Out-Null
    $current = az account show --query id -o tsv 2>&1
    if ($current.Trim() -eq $subscriptionId) {
        Add-Result "Subscription" "PASS" "Active: $subscriptionId"
    } else {
        Add-Result "Subscription" "FAIL" "Could not set subscription $subscriptionId"
    }
} catch {
    Add-Result "Subscription" "FAIL" "Subscription $subscriptionId not accessible"
}

# --- 3. Provider registration ---
Write-Host "Checking provider registration..." -ForegroundColor Yellow
foreach ($provider in $providers) {
    $state = az provider show --namespace $provider --query "registrationState" -o tsv 2>&1
    if ($state.Trim() -eq "Registered") {
        Add-Result "Provider: $provider" "PASS" "Registered"
    } else {
        Write-Host "  Registering $provider..." -ForegroundColor Gray
        az provider register --namespace $provider --wait 2>&1 | Out-Null
        $stateAfter = az provider show --namespace $provider --query "registrationState" -o tsv 2>&1
        if ($stateAfter.Trim() -eq "Registered") {
            Add-Result "Provider: $provider" "PASS" "Registered (just now)"
        } else {
            Add-Result "Provider: $provider" "WARN" "Registration pending: $stateAfter"
        }
    }
}

# --- 4. Permissions check ---
Write-Host "Checking permissions..." -ForegroundColor Yellow
try {
    $roleAssignments = az role assignment list --assignee (az ad signed-in-user show --query id -o tsv 2>&1).Trim() `
        --scope "/subscriptions/$subscriptionId" -o json 2>&1 | ConvertFrom-Json
    $roles = $roleAssignments | ForEach-Object { $_.roleDefinitionName }
    
    if ($roles -contains "Owner") {
        Add-Result "Permissions" "PASS" "Owner role on subscription"
    } elseif ($roles -contains "Contributor") {
        Add-Result "Permissions" "WARN" "Contributor role (may need Role Based Access Administrator for RBAC)"
    } else {
        Add-Result "Permissions" "WARN" "Roles found: $($roles -join ', '). May need Owner or Contributor."
    }
} catch {
    Add-Result "Permissions" "WARN" "Could not verify permissions: $($_.Exception.Message)"
}

# --- 5. Region availability ---
Write-Host "Checking region $location..." -ForegroundColor Yellow
try {
    $regions = az account list-locations --query "[].name" -o json 2>&1 | ConvertFrom-Json
    if ($regions -contains $location) {
        Add-Result "Region: $location" "PASS" "Available in subscription"
    } else {
        Add-Result "Region: $location" "FAIL" "Region not available"
    }
} catch {
    Add-Result "Region" "WARN" "Could not verify region availability"
}

# --- 6. Resource Group ---
Write-Host "Checking/creating resource group..." -ForegroundColor Yellow
$rg = $config.resource_group
try {
    $existing = az group show --name $rg -o json 2>&1 | ConvertFrom-Json
    if ($existing.name -eq $rg) {
        if ($existing.location -eq $location) {
            Add-Result "Resource Group: $rg" "PASS" "Exists in $location"
        } else {
            Add-Result "Resource Group: $rg" "FAIL" "Exists but in $($existing.location), expected $location"
        }
    }
} catch {
    Write-Host "  Creating RG $rg in $location..." -ForegroundColor Gray
    az group create --name $rg --location $location -o none 2>&1
    Add-Result "Resource Group: $rg" "PASS" "Created in $location"
}

# --- Print results ---
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  PRE-FLIGHT RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
foreach ($r in $results) {
    $color = switch ($r.Status) { "PASS" { "Green" } "FAIL" { "Red" } "WARN" { "Yellow" } }
    Write-Host "$($r.Icon) $($r.Status)  $($r.Test): $($r.Detail)" -ForegroundColor $color
}
Write-Host "`n--- Summary: $pass PASS, $fail FAIL, $warn WARN ---" -ForegroundColor Cyan

if ($fail -gt 0) {
    Write-Host "`nPre-flight FAILED. Fix issues above before deploying.`n" -ForegroundColor Red
    exit 1
} else {
    Write-Host "`nPre-flight PASSED. Ready to deploy.`n" -ForegroundColor Green
    exit 0
}
