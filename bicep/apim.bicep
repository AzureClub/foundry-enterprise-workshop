// ============================================================================
// APIM Developer tier — Internal VNet mode
// Deploys: NSG, APIM Subnet, APIM, Private DNS (azure-api.net), RBAC
// Must run AFTER main.bicep (requires existing VNet + Foundry Account)
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

@description('APIM subnet configuration')
param apimSubnetName string = 'snet-apim'
param apimSubnetPrefix string = '192.168.2.0/27'

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

var aiServicesUniqueName = '${aiServicesNamePrefix}-${uniqueSuffix}'
resource aiServices 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' existing = {
  name: aiServicesUniqueName
}

var apimUniqueName = '${apimName}-${uniqueSuffix}'

// ============================================================================
// NSG for APIM subnet (stv2 requirements)
// ============================================================================
resource apimNsg 'Microsoft.Network/networkSecurityGroups@2024-05-01' = {
  name: 'nsg-apim'
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowAPIMManagement'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '3443'
          sourceAddressPrefix: 'ApiManagement'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowAzureLoadBalancer'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '6390'
          sourceAddressPrefix: 'AzureLoadBalancer'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowVNetHTTPS'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'VirtualNetwork'
          access: 'Allow'
          priority: 120
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowStorageOutbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Storage'
          access: 'Allow'
          priority: 100
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowSQLOutbound'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '1433'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: 'Sql'
          access: 'Allow'
          priority: 110
          direction: 'Outbound'
        }
      }
    ]
  }
}

// ============================================================================
// APIM Subnet (added to existing VNet)
// ============================================================================
resource apimSubnet 'Microsoft.Network/virtualNetworks/subnets@2024-05-01' = {
  parent: vnet
  name: apimSubnetName
  properties: {
    addressPrefix: apimSubnetPrefix
    networkSecurityGroup: {
      id: apimNsg.id
    }
  }
}

// ============================================================================
// APIM — Developer tier, Internal VNet mode, System MI
// ============================================================================
resource apim 'Microsoft.ApiManagement/service@2024-06-01-preview' = {
  name: apimUniqueName
  location: location
  sku: {
    name: 'Developer'
    capacity: 1
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    publisherEmail: publisherEmail
    publisherName: publisherName
    virtualNetworkType: 'Internal'
    virtualNetworkConfiguration: {
      subnetResourceId: apimSubnet.id
    }
  }
}

// ============================================================================
// Private DNS zone for Internal mode APIM (azure-api.net)
// ============================================================================
resource apimDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' = {
  name: 'azure-api.net'
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

// Gateway A record
resource dnsRecordGateway 'Microsoft.Network/privateDnsZones/A@2024-06-01' = {
  parent: apimDnsZone
  name: apimUniqueName
  properties: {
    ttl: 3600
    aRecords: [{ ipv4Address: apim.properties.privateIPAddresses[0] }]
  }
}

// Developer Portal A record
resource dnsRecordDeveloper 'Microsoft.Network/privateDnsZones/A@2024-06-01' = {
  parent: apimDnsZone
  name: '${apimUniqueName}.developer'
  properties: {
    ttl: 3600
    aRecords: [{ ipv4Address: apim.properties.privateIPAddresses[0] }]
  }
}

// Management A record
resource dnsRecordManagement 'Microsoft.Network/privateDnsZones/A@2024-06-01' = {
  parent: apimDnsZone
  name: '${apimUniqueName}.management'
  properties: {
    ttl: 3600
    aRecords: [{ ipv4Address: apim.properties.privateIPAddresses[0] }]
  }
}

// SCM A record
resource dnsRecordScm 'Microsoft.Network/privateDnsZones/A@2024-06-01' = {
  parent: apimDnsZone
  name: '${apimUniqueName}.scm'
  properties: {
    ttl: 3600
    aRecords: [{ ipv4Address: apim.properties.privateIPAddresses[0] }]
  }
}

// ============================================================================
// RBAC: APIM MI → Cognitive Services OpenAI User on Foundry account
// ============================================================================
var cognitiveServicesOpenAIUser = '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd'
var azureAIDeveloper = '64702f94-c441-49e6-a78b-ef80e0188fee'

// OpenAI inference (chat completions)
resource apimCogServicesRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiServices.id, apim.id, cognitiveServicesOpenAIUser)
  scope: aiServices
  properties: {
    principalId: apim.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', cognitiveServicesOpenAIUser)
    principalType: 'ServicePrincipal'
  }
}

// Agent Service operations (create agent, threads, runs)
resource apimAiDeveloperRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(aiServices.id, apim.id, azureAIDeveloper)
  scope: aiServices
  properties: {
    principalId: apim.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', azureAIDeveloper)
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Outputs
// ============================================================================
output apimName string = apim.name
output apimGatewayUrl string = apim.properties.gatewayUrl
output apimPrivateIp string = apim.properties.privateIPAddresses[0]
output apimPrincipalId string = apim.identity.principalId
output foundryEndpoint string = 'https://${aiServicesUniqueName}.cognitiveservices.azure.com'
