@description('Azure OpenAI account name.')
param aiServicesName string

@description('Azure OpenAI model deployment name.')
param deploymentName string = 'gpt-4o'

@description('Azure OpenAI model name, e.g. "gpt-35-turbo".')
param modelName string = 'gpt-4o'

resource openAIAccount 'Microsoft.CognitiveServices/accounts@2024-10-01' existing = {
  name: aiServicesName
}

resource openAIDeployment 'Microsoft.CognitiveServices/accounts/deployments@2024-10-01' = {
  name: deploymentName
  parent: openAIAccount
  sku: {
    name: 'Standard'
    capacity: 30
  }
  properties: {
    model: {
      format: 'OpenAI'
      name: modelName
      // version: '0301' // Optionally specify version
    }
  }
}

output deploymentName string = openAIDeployment.name
