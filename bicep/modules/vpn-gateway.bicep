// ============================================================================
// VPN Gateway P2S (for client remote access to VNet resources)
// Uses VpnGw1AZ SKU with Azure AD authentication
// ============================================================================

@description('Azure region')
param location string

@description('GatewaySubnet ID')
param gatewaySubnetId string

// --- VPN PIP (zone-redundant) ---
resource vpnGatewayPip 'Microsoft.Network/publicIPAddresses@2024-05-01' = {
  name: 'pip-vpn-gateway'
  location: location
  sku: { name: 'Standard' }
  zones: ['1', '2', '3']
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// --- VPN Gateway ---
resource vpnGateway 'Microsoft.Network/virtualNetworkGateways@2024-05-01' = {
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
          subnet: { id: gatewaySubnetId }
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

// --- Outputs ---
output vpnGatewayId string = vpnGateway.id
output vpnGatewayPublicIp string = vpnGatewayPip.properties.ipAddress
