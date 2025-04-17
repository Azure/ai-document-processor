param location string
param name string
param tags object = {}
param serviceId string
param subnetId string
param groupIds array = []
param dnsZoneId string

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
  properties:{
    privateDnsZoneConfigs:[
      {
        name:'config1'
        properties:{
          privateDnsZoneId: dnsZoneId
        }
      }
    ]
  }
}

output name string = privateEndpoint.name
