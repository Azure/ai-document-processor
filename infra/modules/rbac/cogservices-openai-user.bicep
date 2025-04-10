param principalIds array
param resourceName string
param principalType string = 'ServicePrincipal'

resource resource 'Microsoft.CognitiveServices/accounts@2023-05-01' existing = {
  name: resourceName
}

// Cognitive Services OpenAI User Role
var roleDefinitionId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '5e0bd9bd-7b93-4f28-af87-19fc36ad61bd') 

resource roleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = [for principalId in principalIds: {
  name: guid(resourceGroup().id, principalId, roleDefinitionId)
  scope: resource
  properties: {
    roleDefinitionId: roleDefinitionId
    principalId: principalId
    principalType: principalType
  }
}]
