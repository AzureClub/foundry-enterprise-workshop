// ============================================================================
// APIM Standard v2 — with Private Endpoint for BYO VNet
// Deploys: APIM Standard v2, Private Endpoint, DNS zone, RBAC
// Must run AFTER main.bicep (requires existing VNet + Foundry Account)
//
// Standard v2 does NOT use VNet injection (no dedicated APIM subnet).
// Instead, private access is via Private Endpoint in the PE subnet.
// This tier is required for the Foundry AI Gateway integration.
// ============================================================================

@description('Azure region')
param location string = 'swedencentral'

@description('APIM name prefix')
param apimName string = 'apim-foundry-test'

@description('Publisher configuration')
param publisherEmail string = 'admin@contoso.com'
param publisherName string = 'Foundry VNet Test'

@description('Existing VNet name (from main.bicep)')
param vnetName string = 'vnet-foundry-test'

@description('PE subnet name — APIM Private Endpoint goes here (from main.bicep)')
param peSubnetName string = 'snet-pe'

@description('Foundry account name prefix (must match main.bicep)')
param aiServicesNamePrefix string = 'ai-foundry-byovnet'

@description('Unique suffix — must match main.bicep')
param uniqueSuffix string = uniqueString(resourceGroup().id)

// ============================================================================
// References to existing resources
// ============================================================================
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
}

resource peSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' existing = {
  parent: vnet
  name: peSubnetName
}

var aiServicesUniqueName = '${aiServicesNamePrefix}-${uniqueSuffix}'
resource aiServices 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: aiServicesUniqueName
}

var apimUniqueName = '${apimName}-${uniqueSuffix}'

// ============================================================================
// APIM — Standard v2 (no VNet injection, uses Private Endpoint)
// Required for Foundry AI Gateway integration
// ============================================================================
resource apim 'Microsoft.ApiManagement/service@2024-06-01-preview' = {
  name: apimUniqueName
  location: location
  sku: {
    name: 'StandardV2'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
  }
}

// ============================================================================
// Private Endpoint for APIM Gateway (in PE subnet)
// Allows VNet resources (Foundry agents, jumpbox) to reach APIM privately
// ============================================================================
resource apimPe 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${apimUniqueName}'
  location: location
  properties: {
    subnet: {
      id: peSubnet.id
    }
    privateLinkServiceConnections: [
      {
        name: 'apim-gateway-connection'
        properties: {
          privateLinkServiceId: apim.id
          groupIds: [
            'Gateway'
          ]
        }
      }
    ]
  }
}

// ============================================================================
// Private DNS zone: privatelink.azure-api.net
// Auto-creates A records for APIM gateway PE
// ============================================================================
resource apimDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'privatelink.azure-api.net'
  location: 'global'
}

resource apimDnsLink 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = {
  parent: apimDnsZone
  name: 'apim-vnet-link'
  location: 'global'
  properties: {
    virtualNetwork: {
      id: vnet.id
    }
    registrationEnabled: false
  }
}

// DNS zone group — automatically manages A records for the PE
resource apimPeDnsGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: apimPe
  name: 'apim-dns-zone-group'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'privatelink-azure-api-net'
        properties: {
          privateDnsZoneId: apimDnsZone.id
        }
      }
    ]
  }
}

// ============================================================================
// RBAC: APIM MI → Cognitive Services OpenAI User on Foundry account
// ============================================================================
var cognitiveServicesOpenAIUser = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'

resource apimCogServicesRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiServices.id, apim.id, cognitiveServicesOpenAIUser)
  scope: aiServices
  properties: {
    principalId: apim.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAIUser)
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Outputs
// ============================================================================
output apimName string = apim.name
output apimGatewayUrl string = apim.properties.gatewayUrl
output apimPrincipalId string = apim.identity.principalId
output apimPrivateEndpointName string = apimPe.name
output foundryEndpoint string = 'https://${aiServicesUniqueName}.cognitiveservices.azure.com'
