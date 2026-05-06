// ============================================================================
// Foundry BYO VNet — Main Orchestrator
// Deploys 9 modules in correct dependency order:
//   Phase 1: networking + dependencies (parallel)
//   Phase 2: ai-services, bastion, vpn-gateway (parallel, need networking)
//   Phase 3: private-endpoints (needs networking + dependencies + ai-services)
//   Phase 4: project (needs ai-services + dependencies, after PE)
//   Phase 5: rbac (needs project MI + account MI)
//   Phase 6: capability-host (needs rbac + connections)
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
// Computed values
// ============================================================================
var aiServicesUniqueName = '${aiServicesName}-${uniqueSuffix}'

// ============================================================================
// Phase 1: Networking + Dependencies (parallel)
// ============================================================================
module networking 'modules/networking.bicep' = {
  name: 'networking'
  params: {
    location: location
    vnetName: vnetName
    vnetAddressPrefix: vnetAddressPrefix
    agentSubnetName: agentSubnetName
    agentSubnetPrefix: agentSubnetPrefix
    peSubnetName: peSubnetName
    peSubnetPrefix: peSubnetPrefix
  }
}

module dependencies 'modules/dependencies.bicep' = {
  name: 'dependencies'
  params: {
    location: location
    uniqueSuffix: uniqueSuffix
  }
}

// ============================================================================
// Phase 2: AI Services Account (needs networking for BYO VNet subnet)
// ============================================================================
module aiServices 'modules/ai-services.bicep' = {
  name: 'ai-services'
  params: {
    location: location
    aiServicesName: aiServicesUniqueName
    agentSubnetId: networking.outputs.subnetIds.agent
    modelName: modelName
    modelFormat: modelFormat
    modelVersion: modelVersion
    modelSkuName: modelSkuName
    modelCapacity: modelCapacity
  }
}

// ============================================================================
// Phase 3: Private Endpoints (needs all resource IDs + networking)
// ============================================================================
module privateEndpoints 'modules/private-endpoints.bicep' = {
  name: 'private-endpoints'
  params: {
    location: location
    peSubnetId: networking.outputs.subnetIds.pe
    dnsZoneIds: networking.outputs.dnsZoneIds
    aiServicesId: aiServices.outputs.aiServicesId
    aiServicesName: aiServices.outputs.aiServicesName
    storageAccountId: dependencies.outputs.storageAccountId
    storageAccountName: dependencies.outputs.storageAccountName
    searchServiceId: dependencies.outputs.searchServiceId
    searchServiceName: dependencies.outputs.searchServiceName
    cosmosAccountId: dependencies.outputs.cosmosAccountId
    cosmosAccountName: dependencies.outputs.cosmosAccountName
  }
}

// ============================================================================
// Phase 4: Project + Connections (after PE for stable provisioning)
// ============================================================================
module project 'modules/project.bicep' = {
  name: 'project'
  dependsOn: [privateEndpoints]
  params: {
    location: location
    aiServicesName: aiServices.outputs.aiServicesName
    projectName: projectName
    projectDescription: projectDescription
    storageAccountName: dependencies.outputs.storageAccountName
    storageAccountId: dependencies.outputs.storageAccountId
    searchServiceName: dependencies.outputs.searchServiceName
    searchServiceId: dependencies.outputs.searchServiceId
    cosmosAccountName: dependencies.outputs.cosmosAccountName
    cosmosAccountId: dependencies.outputs.cosmosAccountId
  }
}

// ============================================================================
// Phase 5: RBAC — 12 role assignments (needs Project MI + Account MI)
// ============================================================================
module rbac 'modules/rbac.bicep' = {
  name: 'rbac'
  params: {
    projectId: project.outputs.projectId
    projectPrincipalId: project.outputs.projectPrincipalId
    aiServicesId: aiServices.outputs.aiServicesId
    accountPrincipalId: aiServices.outputs.aiServicesPrincipalId
    searchServiceName: dependencies.outputs.searchServiceName
    storageAccountName: dependencies.outputs.storageAccountName
    cosmosAccountName: dependencies.outputs.cosmosAccountName
  }
}

// ============================================================================
// Phase 6: Capability Host (needs RBAC complete + connection names)
// ============================================================================
module capabilityHost 'modules/capability-host.bicep' = {
  name: 'capability-host'
  dependsOn: [rbac]
  params: {
    aiServicesName: aiServices.outputs.aiServicesName
    projectName: project.outputs.projectName
    storageConnectionName: project.outputs.connectionStorageName
    searchConnectionName: project.outputs.connectionSearchName
    cosmosConnectionName: project.outputs.connectionCosmosName
  }
}

// ============================================================================
// Bastion + Jumpbox VM (parallel with Phase 2+, needs networking only)
// ============================================================================
module bastion 'modules/bastion.bicep' = if (deployBastion) {
  name: 'bastion'
  params: {
    location: location
    bastionSubnetId: networking.outputs.subnetIds.bastion
    mgmtSubnetId: networking.outputs.subnetIds.mgmt
    vmAdminUsername: vmAdminUsername
    vmAdminPassword: vmAdminPassword
  }
}

// ============================================================================
// VPN Gateway (parallel with Phase 2+, needs networking only)
// ============================================================================
module vpnGateway 'modules/vpn-gateway.bicep' = if (deployVpnGateway) {
  name: 'vpn-gateway'
  params: {
    location: location
    gatewaySubnetId: networking.outputs.subnetIds.gateway
  }
}

// ============================================================================
// Outputs
// ============================================================================
output vnetId string = networking.outputs.vnetId
output agentSubnetId string = networking.outputs.subnetIds.agent
output peSubnetId string = networking.outputs.subnetIds.pe
output aiServicesId string = aiServices.outputs.aiServicesId
output aiServicesName string = aiServices.outputs.aiServicesName
output aiServicesPrincipalId string = aiServices.outputs.aiServicesPrincipalId
output aiServicesEndpoint string = aiServices.outputs.aiServicesEndpoint
output projectId string = project.outputs.projectId
output projectName string = project.outputs.projectName
output storageAccountId string = dependencies.outputs.storageAccountId
output storageAccountName string = dependencies.outputs.storageAccountName
output searchServiceId string = dependencies.outputs.searchServiceId
output searchServiceName string = dependencies.outputs.searchServiceName
output cosmosAccountId string = dependencies.outputs.cosmosAccountId
output cosmosAccountName string = dependencies.outputs.cosmosAccountName
output bastionId string = deployBastion ? bastion!.outputs.bastionId : ''
output jumpboxPrivateIp string = deployBastion ? bastion!.outputs.jumpboxPrivateIp : ''
output vpnGatewayId string = deployVpnGateway ? vpnGateway!.outputs.vpnGatewayId : ''
output vpnGatewayPublicIp string = deployVpnGateway ? vpnGateway!.outputs.vpnGatewayPublicIp : ''
