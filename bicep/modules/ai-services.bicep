// ============================================================================
// Azure AI Foundry Account + Model Deployment
// ============================================================================

@description('Azure region')
param location string

@description('AI Services account name (must be globally unique)')
param aiServicesName string

@description('Agent subnet ARM ID (for BYO VNet networkInjections)')
param agentSubnetId string

@description('Model configuration')
param modelName string
param modelFormat string
param modelVersion string
param modelSkuName string
param modelCapacity int

// --- AI Services Account with BYO VNet ---
resource aiServices 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: aiServicesName
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: aiServicesName
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
    allowProjectManagement: true
    networkInjections: [
      {
        scenario: 'agent'
        subnetArmId: agentSubnetId
        useMicrosoftManagedNetwork: false
      }
    ]
  }
}

// --- Model Deployment ---
resource modelDeployment 'Microsoft.CognitiveServices/accounts/deployments@2025-04-01-preview' = {
  parent: aiServices
  name: modelName
  sku: {
    name: modelSkuName
    capacity: modelCapacity
  }
  properties: {
    model: {
      name: modelName
      format: modelFormat
      version: modelVersion
    }
  }
}

// --- Outputs ---
output aiServicesId string = aiServices.id
output aiServicesName string = aiServices.name
output aiServicesPrincipalId string = aiServices.identity.principalId
output aiServicesEndpoint string = 'https://${aiServicesName}.cognitiveservices.azure.com'
