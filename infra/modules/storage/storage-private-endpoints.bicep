@description('Name of the resource.')
param name string
@description('Location to deploy the resource. Defaults to the location of the resource group.')
param location string = resourceGroup().location
@description('Tags for the resource.')
param tags object = {}

param vnetName string

var abbrs = loadJsonContent('../../abbreviations.json')
var roles = loadJsonContent('../../roles.json')

resource storage 'Microsoft.Storage/storageAccounts@2023-01-01' existing = {
  name: name
}

resource vnet 'Microsoft.Network/virtualNetworks@2024-05-01' existing = {
  name: vnetName
}

resource blobDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.blob.${environment().suffixes.storage}'
}

resource tableDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.table.${environment().suffixes.storage}'
}

resource queueDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.queue.${environment().suffixes.storage}'
}

resource fileDnsZone 'Microsoft.Network/privateDnsZones@2024-06-01' existing = {
  name: 'privatelink.file.${environment().suffixes.storage}'
}

var subnets = reduce(
  map(vnet.properties.subnets, subnet => {
      '${subnet.name}': {
        id: subnet.id
        addressPrefix: subnet.properties.addressPrefix
      }
    }),
  {},
  (cur, acc) => union(cur, acc)
)

module storageblobpe '../network/private-endpoint.bicep' = {
  name: '${name}-storage-blob-pe'
  params: {
    location: location
    name: '${name}${abbrs.storage.storageAccount}${abbrs.security.privateEndpoint}blob'
    tags: tags
    subnetId: subnets['aiSubnet'].id
    serviceId: storage.id
    groupIds: ['blob']
    dnsZoneId: blobDnsZone.id
  }
}

module storagetablepe '../network/private-endpoint.bicep' = {
  name: '${name}-storage-table-pe'
  params: {
    location: location
    name: '${name}${abbrs.storage.storageAccount}${abbrs.security.privateEndpoint}table'
    tags: tags
    subnetId: subnets['aiSubnet'].id
    serviceId: storage.id
    groupIds: ['table']
    dnsZoneId: tableDnsZone.id
  }
}

module storagequeuepe '../network/private-endpoint.bicep' = {
  name: '${name}-storage-queue-pe'
  params: {
    location: location
    name: '${name}${abbrs.storage.storageAccount}${abbrs.security.privateEndpoint}queue'
    tags: tags
    subnetId: subnets['aiSubnet'].id
    serviceId: storage.id
    groupIds: ['queue']
    dnsZoneId: queueDnsZone.id
  }
}

module storagefilepe '../network/private-endpoint.bicep' = {
  name: '${name}-storage-file-pe'
  params: {
    location: location
    name: '${name}${abbrs.storage.storageAccount}${abbrs.security.privateEndpoint}file'
    tags: tags
    subnetId: subnets['aiSubnet'].id
    serviceId: storage.id
    groupIds: ['file']
    dnsZoneId: fileDnsZone.id
  }
}
