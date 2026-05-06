// ============================================================================
// Capability Host — enables Agent runtime on Foundry project
// Must run AFTER all RBAC assignments are complete.
// ============================================================================

@description('AI Services account name')
param aiServicesName string

@description('Project name')
param projectName string

@description('Connection names for agent capabilities')
param storageConnectionName string
param searchConnectionName string
param cosmosConnectionName string

// --- Existing references ---
resource aiServices 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: aiServicesName
}

resource project 'Microsoft.CognitiveServices/accounts/projects@2025-04-01-preview' existing = {
  parent: aiServices
  name: projectName
}

// --- Capability Host ---
resource capabilityHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview' = {
  parent: project
  name: 'default'
  properties: {
    capabilityHostKind: 'Agents'
    vectorStoreConnections: [searchConnectionName]
    storageConnections: [storageConnectionName]
    threadStorageConnections: [cosmosConnectionName]
  }
}

// --- Outputs ---
output capabilityHostId string = capabilityHost.id
