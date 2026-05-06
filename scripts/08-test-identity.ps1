<#
.SYNOPSIS
    Test Managed Identity and RBAC role assignments.
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
Write-Host "  FAZA 5: IDENTITY & RBAC VALIDATION" -ForegroundColor Cyan
Write-Host "========================================`n" -ForegroundColor Cyan

# --- 1. Foundry Account MI ---
Write-Host "Checking Foundry Account Managed Identity..." -ForegroundColor Yellow
$aiAccounts = az cognitiveservices account list --resource-group $rg -o json 2>&1 | ConvertFrom-Json
$mainAccount = $aiAccounts | Where-Object { $_.kind -eq "AIServices" } | Select-Object -First 1

if ($mainAccount) {
    $accountMi = $mainAccount.identity
    if ($accountMi.type -match "SystemAssigned") {
        Add-Result "Account MI" "PASS" "System-assigned, PrincipalId: $($accountMi.principalId.Substring(0,8))..."
    } else {
        Add-Result "Account MI" "FAIL" "No system-assigned MI. Type: $($accountMi.type)"
    }

    # --- 2. Check RBAC on each resource ---
    Write-Host "Checking RBAC role assignments..." -ForegroundColor Yellow

    $requiredRoles = @{
        "Search Index Data Contributor" = $config.rbac_roles.search_index_data_contributor
        "Search Service Contributor" = $config.rbac_roles.search_service_contributor
        "Storage Blob Data Owner" = $config.rbac_roles.storage_blob_data_owner
        "Storage Queue Data Contributor" = $config.rbac_roles.storage_queue_data_contributor
        "Cosmos DB Operator" = $config.rbac_roles.cosmos_db_operator
    }

    # Get all role assignments for the account MI
    $roleAssignments = az role assignment list --assignee $accountMi.principalId --all -o json 2>&1 | ConvertFrom-Json
    $assignedRoleIds = $roleAssignments | ForEach-Object { ($_.roleDefinitionId -split '/')[-1] }

    foreach ($roleName in $requiredRoles.Keys) {
        $roleId = $requiredRoles[$roleName]
        if ($assignedRoleIds -contains $roleId) {
            Add-Result "Account RBAC: $roleName" "PASS" "Assigned"
        } else {
            Add-Result "Account RBAC: $roleName" "WARN" "Not assigned to account MI (may be on project MI)"
        }
    }

    # --- 3. Check Project MI ---
    Write-Host "Checking Project Managed Identity..." -ForegroundColor Yellow
    $projectName = $config.foundry.project_name
    try {
        $projectResource = az cognitiveservices account list --resource-group $rg -o json 2>&1 | ConvertFrom-Json
        # Projects are sub-resources; check via REST
        $accountName = $mainAccount.name
        $projectJson = az rest --method GET `
            --url "https://management.azure.com/subscriptions/$($config.subscription_id)/resourceGroups/$rg/providers/Microsoft.CognitiveServices/accounts/$accountName/projects/$projectName`?api-version=2025-04-01-preview" `
            -o json 2>&1 | ConvertFrom-Json

        if ($projectJson.identity.principalId) {
            Add-Result "Project MI" "PASS" "System-assigned, PrincipalId: $($projectJson.identity.principalId.Substring(0,8))..."

            $projectRoles = az role assignment list --assignee $projectJson.identity.principalId --all -o json 2>&1 | ConvertFrom-Json
            $projectRoleIds = $projectRoles | ForEach-Object { ($_.roleDefinitionId -split '/')[-1] }

            foreach ($roleName in $requiredRoles.Keys) {
                $roleId = $requiredRoles[$roleName]
                if ($projectRoleIds -contains $roleId) {
                    Add-Result "Project RBAC: $roleName" "PASS" "Assigned"
                } else {
                    Add-Result "Project RBAC: $roleName" "FAIL" "NOT assigned to project MI"
                }
            }
        } else {
            Add-Result "Project MI" "FAIL" "No system-assigned MI on project"
        }
    } catch {
        Add-Result "Project MI" "WARN" "Could not check project MI: $($_.Exception.Message)"
    }

} else {
    Add-Result "Foundry Account" "FAIL" "No AIServices account found in $rg"
}

# --- 4. CosmosDB auth type ---
Write-Host "Checking CosmosDB auth configuration..." -ForegroundColor Yellow
$cosmosAccounts = az cosmosdb list --resource-group $rg -o json 2>&1 | ConvertFrom-Json
foreach ($c in $cosmosAccounts) {
    if ($c.disableLocalAuth -eq $true) {
        Add-Result "CosmosDB Auth: $($c.name)" "PASS" "AAD only (local auth disabled)"
    } else {
        Add-Result "CosmosDB Auth: $($c.name)" "WARN" "Local auth enabled — should be AAD only"
    }
}

# --- 5. Storage auth type ---
Write-Host "Checking Storage auth configuration..." -ForegroundColor Yellow
$storageAccounts = az storage account list --resource-group $rg -o json 2>&1 | ConvertFrom-Json
foreach ($sa in $storageAccounts) {
    if ($sa.allowSharedKeyAccess -eq $false) {
        Add-Result "Storage Auth: $($sa.name)" "PASS" "SharedKey disabled (AAD only)"
    } else {
        Add-Result "Storage Auth: $($sa.name)" "WARN" "SharedKey enabled — best practice: disable"
    }
}

# --- Print results ---
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  IDENTITY & RBAC VALIDATION RESULTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
foreach ($r in $results) {
    $color = switch ($r.Status) { "PASS" { "Green" } "FAIL" { "Red" } "WARN" { "Yellow" } }
    Write-Host "$($r.Icon) $($r.Status)  $($r.Test): $($r.Detail)" -ForegroundColor $color
}
Write-Host "`n--- Summary: $pass PASS, $fail FAIL, $warn WARN ---" -ForegroundColor Cyan

if ($fail -gt 0) { exit 1 } else { exit 0 }
