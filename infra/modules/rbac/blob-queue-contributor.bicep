param principalId string
param resourceName string

resource resource 'Microsoft.Storage/storageAccounts@2021-04-01' existing = {
  name: resourceName
}

var queueContributorRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '974c5e8b-45b9-4653-ba55-5f855dd0fb88') // Storage Queue Data Contributor role

resource queueRoleAssignment 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(resourceGroup().id, principalId, queueContributorRoleId)
  scope: resource
  properties: {
    roleDefinitionId: queueContributorRoleId
    principalId: principalId
    principalType: 'ServicePrincipal'
  }
}
