param name string
param location string = resourceGroup().location
param kind string = 'linux'
param sku string = 'P0v3'

@description('Tags.')
param tags object

resource hostingPlan 'Microsoft.Web/serverfarms@2024-04-01' = {
  name: name
  location: location
  sku: {
    name: sku
    capacity: 1
  }
  properties: {
    reserved: true
  }
  kind: kind
  tags : tags
}

output id string = hostingPlan.id
output name string = hostingPlan.name
output location string = hostingPlan.location
output skuName string = hostingPlan.sku.name
