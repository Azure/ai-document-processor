@description('Azure AI Multi Services name. It has to be unique. Type a name followed by your resource group name. (<name>-<resourceGroupName>)')
param aiMultiServicesName string

@description('Location for all resources.')
param location string = resourceGroup().location

@allowed([
  'S0'
])
param sku string = 'S0'

resource aiMultiServices 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: aiMultiServicesName
  location: location
  sku: {
    name: sku
  }
  kind: 'AIServices'
  properties: {
    customSubDomainName: aiMultiServicesName
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
    }    
  }
}

output aiMultiServicesName string = aiMultiServices.name
output aiMultiServicesEndpoint string = aiMultiServices.properties.endpoint
