// ============================================================================
// BYO Dependencies — Storage Account, AI Search, CosmosDB
// ============================================================================

@description('Azure region')
param location string

@description('Unique suffix for resource names')
param uniqueSuffix string

var storageAccountName = 'stfoundry${uniqueSuffix}'
var searchServiceName = 'srch-foundry-${uniqueSuffix}'
var cosmosAccountName = 'cosmos-foundry-${uniqueSuffix}'

// --- Storage Account (Agent file storage) ---
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  kind: 'StorageV2'
  sku: {
    name: 'Standard_GRS'
  }
  properties: {
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    publicNetworkAccess: 'Disabled'
    allowSharedKeyAccess: false
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
  }
}

resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storageAccount
  name: 'default'
}

// --- AI Search (Agent vector store) ---
resource searchService 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: searchServiceName
  location: location
  sku: {
    name: 'standard'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    hostingMode: 'default'
    partitionCount: 1
    replicaCount: 1
    publicNetworkAccess: 'disabled'
    authOptions: {
      aadOrApiKey: {
        aadAuthFailureMode: 'http401WithBearerChallenge'
      }
    }
  }
}

// --- CosmosDB (Agent thread storage) ---
resource cosmosAccount 'Microsoft.DocumentDB/databaseAccounts@2024-11-15' = {
  name: cosmosAccountName
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    databaseAccountOfferType: 'Standard'
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
      }
    ]
    publicNetworkAccess: 'Disabled'
    disableLocalAuth: true
  }
}

// --- Outputs ---
output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output searchServiceId string = searchService.id
output searchServiceName string = searchService.name
output cosmosAccountId string = cosmosAccount.id
output cosmosAccountName string = cosmosAccount.name
