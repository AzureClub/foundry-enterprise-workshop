using './main.bicep'

param location = 'swedencentral'
param aiServicesName = 'ai-foundry-byovnet'
param modelName = 'gpt-4.1'
param modelFormat = 'OpenAI'
param modelVersion = '2025-04-14'
param modelSkuName = 'GlobalStandard'
param modelCapacity = 30
param projectName = 'project-agent-test'
param projectDescription = 'Foundry Agent with BYO VNet network isolation test'
param vnetName = 'vnet-foundry-test'
param vnetAddressPrefix = '192.168.0.0/16'
param agentSubnetName = 'snet-agent'
param agentSubnetPrefix = '192.168.0.0/24'
param peSubnetName = 'snet-pe'
param peSubnetPrefix = '192.168.1.0/24'
param deployBastion = true
param vmAdminUsername = 'azureadmin'
param vmAdminPassword = readEnvironmentVariable('VM_ADMIN_PASSWORD', '')
param deployVpnGateway = true
