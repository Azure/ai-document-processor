@description('That name is the name of our application. It has to be unique.Type a name followed by your resource group name. (<name>-<resourceGroupName>)')
param aiServicesName string = 'aiServices-${uniqueString(resourceGroup().id)}'

@description('Location for all resources.')
param location string = resourceGroup().location

@allowed([
  'S0'
])
param sku string = 'S0'

@description('Azure OpenAI model deployment name.')
param deploymentName string = 'gpt-4o'

@description('Azure OpenAI model name, e.g. "gpt-35-turbo".')
param modelName string = 'gpt-4o'

resource openAIAccount 'Microsoft.CognitiveServices/accounts@2023-05-01' = {
  name: aiServicesName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  sku: {
    name: sku
  }
  kind: 'OpenAI'
  properties: {
    publicNetworkAccess: 'Enabled'
    // restore: true
  }
}

resource openAIDeployment 'Microsoft.CognitiveServices/accounts/deployments@2023-05-01' = {
  name: deploymentName
  parent: openAIAccount
  sku: {
    name: 'Standard'
    capacity: 40

  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      // version: '0301' // Optionally specify version
    }
  }
}

output AOAI_ENDPOINT string = openAIAccount.properties.endpoint
