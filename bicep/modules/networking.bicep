// ============================================================================
// Networking — VNet, 6 Subnets, 6 Private DNS Zones, VNet Links
// ============================================================================

@description('Azure region')
param location string

@description('VNet name')
param vnetName string

@description('VNet address space')
param vnetAddressPrefix string

@description('Agent subnet (delegated to Microsoft.App/environments)')
param agentSubnetName string
param agentSubnetPrefix string

@description('Private Endpoint subnet')
param peSubnetName string
param peSubnetPrefix string

// --- VNet with 6 subnets ---
resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [vnetAddressPrefix]
    }
    subnets: [
      {
        name: agentSubnetName
        properties: {
          addressPrefix: agentSubnetPrefix
          delegations: [
            {
              name: 'Microsoft.App.environments'
              properties: {
                serviceName: 'Microsoft.App/environments'
              }
            }
          ]
        }
      }
      {
        name: peSubnetName
        properties: {
          addressPrefix: peSubnetPrefix
        }
      }
      {
        name: 'AzureBastionSubnet'
        properties: {
          addressPrefix: '192.168.3.0/26'
        }
      }
      {
        name: 'snet-mgmt'
        properties: {
          addressPrefix: '192.168.4.0/27'
        }
      }
      {
        name: 'GatewaySubnet'
        properties: {
          addressPrefix: '192.168.5.0/27'
        }
      }
      {
        // APIM subnet — address space reserved here to prevent re-deploy removal.
        // NSG is attached by apim.bicep deployment.
        name: 'snet-apim'
        properties: {
          addressPrefix: '192.168.2.0/27'
        }
      }
    ]
  }
}

// --- Private DNS Zones ---
var privateDnsZoneNames = {
  cognitiveservices: 'privatelink.cognitiveservices.azure.com'
  openai: 'privatelink.openai.azure.com'
  servicesai: 'privatelink.services.ai.azure.com'
  search: 'privatelink.search.windows.net'
  blob: 'privatelink.blob.core.windows.net'
  cosmos: 'privatelink.documents.azure.com'
}

var dnsZoneList = [
  privateDnsZoneNames.cognitiveservices
  privateDnsZoneNames.openai
  privateDnsZoneNames.servicesai
  privateDnsZoneNames.search
  privateDnsZoneNames.blob
  privateDnsZoneNames.cosmos
]

resource dnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [
  for zone in dnsZoneList: {
    name: zone
    location: 'global'
  }
]

resource dnsZoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [
  for (zone, i) in dnsZoneList: {
    name: '${zone}-link'
    parent: dnsZones[i]
    location: 'global'
    properties: {
      virtualNetwork: {
        id: vnet.id
      }
      registrationEnabled: false
    }
  }
]

// --- Outputs (named, not positional) ---
output vnetId string = vnet.id

output subnetIds object = {
  agent: vnet.properties.subnets[0].id
  pe: vnet.properties.subnets[1].id
  bastion: vnet.properties.subnets[2].id
  mgmt: vnet.properties.subnets[3].id
  gateway: vnet.properties.subnets[4].id
  apim: vnet.properties.subnets[5].id
}

output dnsZoneIds object = {
  cognitiveservices: dnsZones[0].id
  openai: dnsZones[1].id
  servicesai: dnsZones[2].id
  search: dnsZones[3].id
  blob: dnsZones[4].id
  cosmos: dnsZones[5].id
}
