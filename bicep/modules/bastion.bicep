// ============================================================================
// Azure Bastion + Jumpbox VM (for portal access testing via ai.azure.com)
// ============================================================================

@description('Azure region')
param location string

@description('AzureBastionSubnet ID')
param bastionSubnetId string

@description('Management subnet ID (snet-mgmt)')
param mgmtSubnetId string

@description('VM admin credentials')
param vmAdminUsername string

@secure()
param vmAdminPassword string

// --- Bastion PIP ---
resource bastionPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-bastion'
  location: location
  sku: { name: 'Standard' }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// --- Bastion Host ---
resource bastion 'Microsoft.Network/bastionHosts@2024-05-01' = {
  name: 'bastion-foundry-test'
  location: location
  sku: { name: 'Standard' }
  properties: {
    ipConfigurations: [
      {
        name: 'bastionIpConfig'
        properties: {
          publicIPAddress: { id: bastionPip.id }
          subnet: { id: bastionSubnetId }
        }
      }
    ]
  }
}

// --- Jumpbox NIC ---
resource jumpboxNic 'Microsoft.Network/networkInterfaces@2024-05-01' = {
  name: 'nic-jumpbox'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Dynamic'
          subnet: { id: mgmtSubnetId }
        }
      }
    ]
  }
}

// --- Jumpbox VM (Windows 11) ---
resource jumpboxVm 'Microsoft.Compute/virtualMachines@2024-07-01' = {
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

// --- Outputs ---
output bastionId string = bastion.id
output jumpboxPrivateIp string = jumpboxNic.properties.ipConfigurations[0].properties.privateIPAddress
