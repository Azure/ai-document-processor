param location string
param name string
param tags object = {}
param serviceId string
param subnetId string
param groupIds array = []
// Single DNS zone (existing callers). Optional when dnsZoneIds is provided.
param dnsZoneId string = ''
// Multiple DNS zones (e.g. AI Foundry needs cognitiveservices + openai + ai.azure.com zones).
// When provided, takes precedence over dnsZoneId.
param dnsZoneIds array = []

var effectiveZoneIds = !empty(dnsZoneIds) ? dnsZoneIds : [dnsZoneId]

resource privateEndpoint 'Microsoft.Network/privateEndpoints@2024-05-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    subnet: {
      id: subnetId
    }
    privateLinkServiceConnections: [
      {
        name: 'privatelinkServiceonnection'
        properties: {
          privateLinkServiceId: serviceId
          groupIds: groupIds
        }
      }
    ]
  }
}

resource privateDnsZoneGroup 'Microsoft.Network/privateEndpoints/privateDnsZoneGroups@2024-05-01' = {
  parent: privateEndpoint
  name: '${name}-group'
  properties: {
    privateDnsZoneConfigs: [for (zoneId, i) in effectiveZoneIds: {
      name: 'config${i + 1}'
      properties: {
        privateDnsZoneId: zoneId
      }
    }]
  }
}

output name string = privateEndpoint.name
