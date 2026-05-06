// ============================================================================
// Foundry BYO VNet - Main Bicep Template
// Deploys: VNet, Subnets, Foundry Account, Project, PE, DNS, RBAC
// Based on: microsoft-foundry/foundry-samples/15-private-network-standard-agent-setup
// ============================================================================

@description('Azure region for all resources')
param location string = 'swedencentral'

@description('Foundry account name prefix')
param aiServicesName string = 'ai-foundry-byovnet'

@description('Model deployment configuration')
param modelName string = 'gpt-4.1'
param modelFormat string = 'OpenAI'
param modelVersion string = '2025-04-14'
param modelSkuName string = 'GlobalStandard'
param modelCapacity int = 30

@description('Project configuration')
param projectName string = 'project-agent-test'
param projectDescription string = 'Foundry Agent with BYO VNet network isolation test'

@description('VNet configuration')
param vnetName string = 'vnet-foundry-test'
param vnetAddressPrefix string = '192.168.0.0/16'
param agentSubnetName string = 'snet-agent'
param agentSubnetPrefix string = '192.168.0.0/24'
param peSubnetName string = 'snet-pe'
param peSubnetPrefix string = '192.168.1.0/24'

@description('Bastion + Jumpbox VM for portal access testing')
param deployBastion bool = true
param vmAdminUsername string = 'azureadmin'
@secure()
param vmAdminPassword string

@description('VPN P2S Gateway for client remote access')
param deployVpnGateway bool = true

@description('Unique suffix for resource names')
param uniqueSuffix string = uniqueString(resourceGroup().id)

// ============================================================================
// Variables
// ============================================================================
var aiServicesUniqueName = '${aiServicesName}-${uniqueSuffix}'
var storageAccountName = 'stfoundry${uniqueSuffix}'
var searchServiceName = 'srch-foundry-${uniqueSuffix}'
var cosmosAccountName = 'cosmos-foundry-${uniqueSuffix}'

var privateDnsZones = [
  'privatelink.cognitiveservices.azure.com'
  'privatelink.openai.azure.com'
  'privatelink.services.ai.azure.com'
  'privatelink.search.windows.net'
  'privatelink.blob.core.windows.net'
  'privatelink.documents.azure.com'
]

// ============================================================================
// VNet + Subnets
// ============================================================================
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

// ============================================================================
// Private DNS Zones + VNet Links
// ============================================================================
resource dnsZones 'Microsoft.Network/privateDnsZones@2024-06-01' = [
  for zone in privateDnsZones: {
    name: zone
    location: 'global'
  }
]

resource dnsZoneLinks 'Microsoft.Network/privateDnsZones/virtualNetworkLinks@2024-06-01' = [
  for (zone, i) in privateDnsZones: {
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

// ============================================================================
// Storage Account (BYO - Agent file storage)
// ============================================================================
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

// ============================================================================
// Azure AI Search (BYO - Agent vector store)
// ============================================================================
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

// ============================================================================
// Cosmos DB (BYO - Agent thread storage)
// ============================================================================
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

// ============================================================================
// Azure AI Foundry Account (Cognitive Services)
// ============================================================================
resource aiServices 'Microsoft.CognitiveServices/accounts@2025-04-01-preview' = {
  name: aiServicesUniqueName
  location: location
  kind: 'AIServices'
  sku: {
    name: 'S0'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    customSubDomainName: aiServicesUniqueName
    publicNetworkAccess: 'Disabled'
    networkAcls: {
      defaultAction: 'Deny'
      bypass: 'AzureServices'
    }
    allowProjectManagement: true
    networkInjections: [
      {
        scenario: 'agent'
        subnetArmId: resourceId('Microsoft.Network/virtualNetworks/subnets', vnetName, agentSubnetName)
        useMicrosoftManagedNetwork: false
      }
    ]
  }
}

// ============================================================================
// Model Deployment
// ============================================================================
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

// ============================================================================
// Foundry Project
// ============================================================================
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
  dependsOn: [modelDeployment, peAiServices] // serialize: wait for account + PE to be fully provisioned
}

// ============================================================================
// Project Connections (Storage, AI Search, CosmosDB)
// ============================================================================
resource connectionStorage 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: project
  name: 'connection-storage'
  properties: {
    category: 'AzureStorageAccount'
    authType: 'AAD'
    target: 'https://${storageAccount.name}.blob.${environment().suffixes.storage}'
    metadata: {
      ResourceId: storageAccount.id
      AccountName: storageAccount.name
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
    target: 'https://${searchService.name}.search.windows.net'
    metadata: {
      ResourceId: searchService.id
    }
  }
}

resource connectionCosmos 'Microsoft.CognitiveServices/accounts/projects/connections@2025-04-01-preview' = {
  parent: project
  name: 'connection-cosmos'
  properties: {
    category: 'CosmosDB'
    authType: 'AAD'
    target: 'https://${cosmosAccount.name}.documents.azure.com:443/'
    metadata: {
      ApiType: 'Azure'
      ResourceId: cosmosAccount.id
      DatabaseName: ''
      CollectionName: ''
    }
  }
}

// ============================================================================
// RBAC Role Assignments — Project MI → BYO resources (pre-capability host)
// ============================================================================
var roleDefinitions = {
  searchIndexDataContributor: '8ebe5a00-799e-43f5-93ac-243d3dce84a7'
  searchServiceContributor: '7ca78c08-252a-4471-8644-bb5ff32d4ba0'
  storageBlobDataOwner: 'b7e6dc6d-f1e8-4753-8033-0f276bb0955b'
  storageAccountContributor: '17d1049b-9a84-46fb-8f53-869881c3d3ab'
  storageQueueDataContributor: '974c5e8b-45b9-4653-ba55-5f855dd0fb88'
  cosmosDbOperator: '230815da-be43-4aae-9cb4-875f7bd000aa'
}

// AI Search RBAC (project MI)
resource searchRbac1 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, project.id, roleDefinitions.searchIndexDataContributor)
  scope: searchService
  properties: {
    principalId: project.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.searchIndexDataContributor)
    principalType: 'ServicePrincipal'
  }
}

resource searchRbac2 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, project.id, roleDefinitions.searchServiceContributor)
  scope: searchService
  properties: {
    principalId: project.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.searchServiceContributor)
    principalType: 'ServicePrincipal'
  }
}

// Storage RBAC (project MI)
resource storageRbac1 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, project.id, roleDefinitions.storageBlobDataOwner)
  scope: storageAccount
  properties: {
    principalId: project.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.storageBlobDataOwner)
    principalType: 'ServicePrincipal'
  }
}

resource storageRbac2 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, project.id, roleDefinitions.storageAccountContributor)
  scope: storageAccount
  properties: {
    principalId: project.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.storageAccountContributor)
    principalType: 'ServicePrincipal'
  }
}

resource storageRbac3 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, project.id, roleDefinitions.storageQueueDataContributor)
  scope: storageAccount
  properties: {
    principalId: project.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.storageQueueDataContributor)
    principalType: 'ServicePrincipal'
  }
}

// CosmosDB RBAC - control plane (project MI)
resource cosmosRbac1 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(cosmosAccount.id, project.id, roleDefinitions.cosmosDbOperator)
  scope: cosmosAccount
  properties: {
    principalId: project.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.cosmosDbOperator)
    principalType: 'ServicePrincipal'
  }
}

// CosmosDB data plane RBAC - required when disableLocalAuth=true
// Built-in Data Contributor role ID: 00000000-0000-0000-0000-000000000002
resource cosmosDataRbacProject 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: cosmosAccount
  name: guid(cosmosAccount.id, project.id, 'cosmos-data-contributor')
  properties: {
    principalId: project.identity.principalId
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    scope: cosmosAccount.id
  }
}

resource cosmosDataRbacAccount 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  parent: cosmosAccount
  name: guid(cosmosAccount.id, aiServices.id, 'cosmos-data-contributor')
  properties: {
    principalId: aiServices.identity.principalId
    roleDefinitionId: '${cosmosAccount.id}/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
    scope: cosmosAccount.id
  }
}

// Account MI also needs search/storage roles for account-level operations
resource searchRbacAccount1 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(searchService.id, aiServices.id, roleDefinitions.searchIndexDataContributor)
  scope: searchService
  properties: {
    principalId: aiServices.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.searchIndexDataContributor)
    principalType: 'ServicePrincipal'
  }
}

resource storageRbacAccount1 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, aiServices.id, roleDefinitions.storageBlobDataOwner)
  scope: storageAccount
  properties: {
    principalId: aiServices.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.storageBlobDataOwner)
    principalType: 'ServicePrincipal'
  }
}

resource storageQueueRbacAccount 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(storageAccount.id, aiServices.id, roleDefinitions.storageQueueDataContributor)
  scope: storageAccount
  properties: {
    principalId: aiServices.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.storageQueueDataContributor)
    principalType: 'ServicePrincipal'
  }
}

resource cosmosRbacAccount1 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(cosmosAccount.id, aiServices.id, roleDefinitions.cosmosDbOperator)
  scope: cosmosAccount
  properties: {
    principalId: aiServices.identity.principalId
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', roleDefinitions.cosmosDbOperator)
    principalType: 'ServicePrincipal'
  }
}

// ============================================================================
// Capability Host (enables agent runtime on project)
// ============================================================================
resource capabilityHost 'Microsoft.CognitiveServices/accounts/projects/capabilityHosts@2025-04-01-preview' = {
  parent: project
  name: 'default'
  properties: {
    capabilityHostKind: 'Agents'
    vectorStoreConnections: [connectionSearch.name]
    storageConnections: [connectionStorage.name]
    threadStorageConnections: [connectionCosmos.name]
  }
  dependsOn: [
    searchRbac1
    searchRbac2
    storageRbac1
    storageRbac2
    storageRbac3
    cosmosRbac1
    cosmosDataRbacProject
    cosmosDataRbacAccount
    searchRbacAccount1
    storageRbacAccount1
    cosmosRbacAccount1
  ]
}
resource peAiServices 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: 'pe-${aiServicesUniqueName}'
  location: location
  properties: {
    subnet: {
      id: vnet.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: 'ai-services-connection'
        properties: {
          privateLinkServiceId: aiServices.id
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
    subnet: {
      id: vnet.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: 'storage-connection'
        properties: {
          privateLinkServiceId: storageAccount.id
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
    subnet: {
      id: vnet.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: 'search-connection'
        properties: {
          privateLinkServiceId: searchService.id
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
    subnet: {
      id: vnet.properties.subnets[1].id
    }
    privateLinkServiceConnections: [
      {
        name: 'cosmos-connection'
        properties: {
          privateLinkServiceId: cosmosAccount.id
          groupIds: ['Sql']
        }
      }
    ]
  }
}

// ============================================================================
// Private DNS Zone Groups (auto-register A records)
// ============================================================================
resource dnsGroupAiServices 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: peAiServices
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'cognitiveservices'
        properties: { privateDnsZoneId: dnsZones[0].id }
      }
      {
        name: 'openai'
        properties: { privateDnsZoneId: dnsZones[1].id }
      }
      {
        name: 'servicesai'
        properties: { privateDnsZoneId: dnsZones[2].id }
      }
    ]
  }
}

resource dnsGroupStorage 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: peStorage
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'blob'
        properties: { privateDnsZoneId: dnsZones[4].id }
      }
    ]
  }
}

resource dnsGroupSearch 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: peSearch
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'search'
        properties: { privateDnsZoneId: dnsZones[3].id }
      }
    ]
  }
}

resource dnsGroupCosmos 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: peCosmos
  name: 'default'
  properties: {
    privateDnsZoneConfigs: [
      {
        name: 'cosmos'
        properties: { privateDnsZoneId: dnsZones[5].id }
      }
    ]
  }
}

// ============================================================================
// Outputs
// ============================================================================
output vnetId string = vnet.id
output agentSubnetId string = vnet.properties.subnets[0].id
output peSubnetId string = vnet.properties.subnets[1].id
output aiServicesId string = aiServices.id
output aiServicesName string = aiServices.name
output aiServicesPrincipalId string = aiServices.identity.principalId
output aiServicesEndpoint string = 'https://${aiServicesUniqueName}.cognitiveservices.azure.com'
output projectId string = project.id
output projectName string = project.name
output storageAccountId string = storageAccount.id
output storageAccountName string = storageAccount.name
output searchServiceId string = searchService.id
output searchServiceName string = searchService.name
output cosmosAccountId string = cosmosAccount.id
output cosmosAccountName string = cosmosAccount.name

// ============================================================================
// Azure Bastion + Jumpbox VM (for portal access testing)
// ============================================================================
resource bastionPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (deployBastion) {
  name: 'pip-bastion'
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource bastion 'Microsoft.Network/bastionHosts@2024-05-01' = if (deployBastion) {
  name: 'bastion-foundry-test'
  location: location
  sku: { name: 'Standard' }
  properties: {
    ipConfigurations: [
      {
        name: 'bastionIpConfig'
        properties: {
          publicIPAddress: { id: bastionPip.id }
          subnet: { id: vnet.properties.subnets[2].id } // AzureBastionSubnet
        }
      }
    ]
  }
}

resource jumpboxNic 'Microsoft.Network/networkInterfaces@2024-05-01' = if (deployBastion) {
  name: 'nic-jumpbox'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: { id: vnet.properties.subnets[3].id } // snet-mgmt
        }
      }
    ]
  }
}

resource jumpboxVm 'Microsoft.Compute/virtualMachines@2024-07-01' = if (deployBastion) {
  name: 'vm-jumpbox'
  location: location
  properties: {
    hardwareProfile: { vmSize: 'Standard_B2s' }
    osProfile: {
      computerName: 'jumpbox'
      adminUsername: vmAdminUsername
      adminPassword: vmAdminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'MicrosoftWindowsDesktop'
        offer: 'windows-11'
        sku: 'win11-24h2-pro'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: { storageAccountType: 'Standard_LRS' }
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: jumpboxNic.id }]
    }
  }
}

// ============================================================================
// VPN Gateway P2S (for client remote access)
// ============================================================================
resource vpnGatewayPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = if (deployVpnGateway) {
  name: 'pip-vpn-gateway'
  location: location
  sku: { name: 'Standard' }
  zones: ['1', '2', '3']
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2024-05-01' = if (deployVpnGateway) {
  name: 'vpngw-foundry-test'
  location: location
  properties: {
    gatewayType: 'Vpn'
    vpnType: 'RouteBased'
    sku: { name: 'VpnGw1AZ', tier: 'VpnGw1AZ' }
    ipConfigurations: [
      {
        name: 'default'
        properties: {
          publicIPAddress: { id: vpnGatewayPip.id }
          subnet: { id: vnet.properties.subnets[4].id } // GatewaySubnet
        }
      }
    ]
    vpnClientConfiguration: {
      vpnClientAddressPool: {
        addressPrefixes: ['172.16.0.0/24']
      }
      vpnClientProtocols: ['OpenVPN']
      vpnAuthenticationTypes: ['AAD']
      aadTenant: 'https://login.microsoftonline.com/${subscription().tenantId}'
      aadAudience: 'c632b3df-fb67-4d84-bdcf-b95ad541b5c8'
      aadIssuer: 'https://sts.windows.net/${subscription().tenantId}/'
    }
  }
}

// Additional outputs for portal access
output bastionId string = deployBastion ? bastion.id : ''
output jumpboxPrivateIp string = deployBastion ? jumpboxNic.properties.ipConfigurations[0].properties.privateIPAddress : ''
output vpnGatewayId string = deployVpnGateway ? vpnGateway.id : ''
output vpnGatewayPublicIp string = deployVpnGateway ? vpnGatewayPip.properties.ipAddress : ''
