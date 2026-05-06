// ============================================================================
// Private Endpoints + DNS Zone Groups for all services
// ============================================================================

@description('Azure region')
param location string

@description('PE subnet ID')
param peSubnetId string

@description('DNS zone IDs (named object from networking module)')
param dnsZoneIds object

@description('AI Services')
param aiServicesId string
param aiServicesName string

@description('Storage Account')
param storageAccountId string
param storageAccountName string

@description('AI Search')
param searchServiceId string
param searchServiceName string

@description('CosmosDB')
param cosmosAccountId string
param cosmosAccountName string

// --- Private Endpoints ---
resource peAiServices 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${aiServicesName}'
  location: location
  properties: {
    subnet: { id: peSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'ai-services-connection'
        properties: {
          privateLinkServiceId: aiServicesId
          groupIds: ['account']
        }
      }
    ]
  }
}

resource peStorage 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${storageAccountName}'
  location: location
  properties: {
    subnet: { id: peSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'storage-connection'
        properties: {
          privateLinkServiceId: storageAccountId
          groupIds: ['blob']
        }
      }
    ]
  }
}

resource peSearch 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${searchServiceName}'
  location: location
  properties: {
    subnet: { id: peSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'search-connection'
        properties: {
          privateLinkServiceId: searchServiceId
          groupIds: ['searchService']
        }
      }
    ]
  }
}

resource peCosmos 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${cosmosAccountName}'
  location: location
  properties: {
    subnet: { id: peSubnetId }
    privateLinkServiceConnections: [
      {
        name: 'cosmos-connection'
        properties: {
          privateLinkServiceId: cosmosAccountId
          groupIds: ['Sql']
        }
      }
    ]
  }
}

// --- DNS Zone Groups (auto-register A records) ---
resource dnsGroupAiServices 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: peAiServices
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'cognitiveservices', properties: { privateDnsZoneId: dnsZoneIds.cognitiveservices } }
      { name: 'openai', properties: { privateDnsZoneId: dnsZoneIds.openai } }
      { name: 'servicesai', properties: { privateDnsZoneId: dnsZoneIds.servicesai } }
    ]
  }
}

resource dnsGroupStorage 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: peStorage
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'blob', properties: { privateDnsZoneId: dnsZoneIds.blob } }
    ]
  }
}

resource dnsGroupSearch 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: peSearch
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'search', properties: { privateDnsZoneId: dnsZoneIds.search } }
    ]
  }
}

resource dnsGroupCosmos 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: peCosmos
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      { name: 'cosmos', properties: { privateDnsZoneId: dnsZoneIds.cosmos } }
    ]
  }
}

// --- Outputs ---
output peAiServicesId string = peAiServices.id
output peStorageId string = peStorage.id
output peSearchId string = peSearch.id
output peCosmosId string = peCosmos.id
