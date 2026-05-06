// ============================================================================
// RBAC Role Assignments — Project MI + Account MI → BYO resources
// 12 assignments total: 7 for Project MI, 5 for Account MI
// ============================================================================

@description('Project resource ID (for deterministic guid names)')
param projectId string

@description('Project Managed Identity principal ID')
param projectPrincipalId string

@description('AI Services resource ID (for deterministic guid names)')
param aiServicesId string

@description('AI Services Managed Identity principal ID')
param accountPrincipalId string

@description('Resource names (for existing references within same RG)')
param searchServiceName string
param storageAccountName string
param cosmosAccountName string

// --- Role definition IDs ---
var roles = {
  searchIndexDataContributor: '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
  searchServiceContributor: '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
  storageBlobDataOwner: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  storageAccountContributor: '17d1049b-9a84-46fb-8f53-869881c3d3ab'
  storageQueueDataContributor: '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
  cosmosDbOperator: '230815da-be43-4aae-9cb4-875f7bd000aa'
}

// --- Existing resources (for scoping role assignments) ---
resource searchService 'Microsoft.Search/searchServices@2024-06-01-preview' existing = {
  name: searchServiceName
}

resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' existing = {
  name: cosmosAccountName
}

// ============================================================================
// Project MI → AI Search (2 roles)
// ============================================================================
resource searchRbac1 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, projectId, roles.searchIndexDataContributor)
  scope: searchService
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.searchIndexDataContributor)
    principalType: 'ServicePrincipal'
  }
}

resource searchRbac2 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, projectId, roles.searchServiceContributor)
  scope: searchService
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.searchServiceContributor)
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Project MI → Storage (3 roles)
// ============================================================================
resource storageRbac1 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, projectId, roles.storageBlobDataOwner)
  scope: storageAccount
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataOwner)
    principalType: 'ServicePrincipal'
  }
}

resource storageRbac2 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, projectId, roles.storageAccountContributor)
  scope: storageAccount
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageAccountContributor)
    principalType: 'ServicePrincipal'
  }
}

resource storageRbac3 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, projectId, roles.storageQueueDataContributor)
  scope: storageAccount
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageQueueDataContributor)
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Project MI → CosmosDB (1 ARM + 1 data plane)
// ============================================================================
resource cosmosRbac1 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(cosmosAccount.id, projectId, roles.cosmosDbOperator)
  scope: cosmosAccount
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.cosmosDbOperator)
    principalType: 'ServicePrincipal'
  }
}

resource cosmosDataRbacProject 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: cosmosAccount
  name: guid(cosmosAccount.id, projectId, 'cosmos-data-contributor')
  properties: {
    principalId: projectPrincipalId
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    scope: cosmosAccount.id
  }
}

// ============================================================================
// Account MI → AI Search (1 role)
// ============================================================================
resource searchRbacAccount1 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, aiServicesId, roles.searchIndexDataContributor)
  scope: searchService
  properties: {
    principalId: accountPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.searchIndexDataContributor)
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Account MI → Storage (2 roles)
// ============================================================================
resource storageRbacAccount1 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, aiServicesId, roles.storageBlobDataOwner)
  scope: storageAccount
  properties: {
    principalId: accountPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageBlobDataOwner)
    principalType: 'ServicePrincipal'
  }
}

resource storageQueueRbacAccount 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, aiServicesId, roles.storageQueueDataContributor)
  scope: storageAccount
  properties: {
    principalId: accountPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.storageQueueDataContributor)
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Account MI → CosmosDB (1 ARM + 1 data plane)
// ============================================================================
resource cosmosRbacAccount1 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(cosmosAccount.id, aiServicesId, roles.cosmosDbOperator)
  scope: cosmosAccount
  properties: {
    principalId: accountPrincipalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roles.cosmosDbOperator)
    principalType: 'ServicePrincipal'
  }
}

resource cosmosDataRbacAccount 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: cosmosAccount
  name: guid(cosmosAccount.id, aiServicesId, 'cosmos-data-contributor')
  properties: {
    principalId: accountPrincipalId
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    scope: cosmosAccount.id
  }
}
