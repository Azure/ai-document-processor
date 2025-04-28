@description('That name is the name of our application. It has to be unique.Type a name followed by your resource group name. (<name>-<resourceGroupName>)')
param aoaiName string

@description('Location for all resources.')
param location string = resourceGroup().location
param customSubDomainName string = aoaiName
@allowed([
  'S0'
])
param sku string = 'S0'
param kind string = 'OpenAI'
param publicNetworkAccess string = 'Enabled'

resource openAIAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: aoaiName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: sku
  }
  kind: kind
  properties: {
    customSubDomainName: customSubDomainName
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: 'Allow'
      virtualNetworkRules: []
      ipRules: []
    }
  }
}

output AOAI_ENDPOINT string = openAIAccount.properties.endpoint
output AOAI_API_KEY string = openAIAccount.listKeys().key1
output name string = openAIAccount.name
output id string = openAIAccount.id
