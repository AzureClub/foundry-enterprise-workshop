// ============================================================================
// Foundry Project + Connections (Storage, AI Search, CosmosDB)
// ============================================================================

@description('Azure region')
param location string

@description('AI Services account name (parent)')
param aiServicesName string

@description('Project configuration')
param projectName string
param projectDescription string

@description('Storage Account')
param storageAccountName string
param storageAccountId string

@description('AI Search')
param searchServiceName string
param searchServiceId string

@description('CosmosDB')
param cosmosAccountName string
param cosmosAccountId string

// --- Reference existing AI Services account ---
resource aiServices 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: aiServicesName
}

// --- Project ---
resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' = {
  parent: aiServices
  name: projectName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    description: projectDescription
  }
}

// --- Connections ---
resource connectionStorage 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: project
  name: 'connection-storage'
  properties: {
    category: 'AzureStorageAccount'
    authType: 'AAD'
    target: 'https://${storageAccountName}.blob.${environment().suffixes.storage}'
    metadata: {
      ResourceId: storageAccountId
      AccountName: storageAccountName
      ContainerName: 'default'
    }
  }
}

resource connectionSearch 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: project
  name: 'connection-search'
  properties: {
    category: 'CognitiveSearch'
    authType: 'AAD'
    target: 'https://${searchServiceName}.search.windows.net'
    metadata: {
      ResourceId: searchServiceId
    }
  }
}

resource connectionCosmos 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: project
  name: 'connection-cosmos'
  properties: {
    category: 'CosmosDB'
    authType: 'AAD'
    target: 'https://${cosmosAccountName}.documents.azure.com:443/'
    metadata: {
      ApiType: 'Azure'
      ResourceId: cosmosAccountId
      DatabaseName: ''
      CollectionName: ''
    }
  }
}

// --- Outputs ---
output projectId string = project.id
output projectName string = project.name
output projectPrincipalId string = project.identity.principalId
output connectionStorageName string = connectionStorage.name
output connectionSearchName string = connectionSearch.name
output connectionCosmosName string = connectionCosmos.name
