param principalId string
param resourceName string
param roleDefinitionGuid string = '00000000-0000-0000-0000-000000000002' // Cosmos DB Built-in Data Contributor

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2021-04-15' existing = {
  name: resourceName
}

var computedRoleDefinitionId = resourceId(resourceGroup().name, 'Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions', resourceName, roleDefinitionGuid)

resource roleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = {
  name: guid(resourceGroup().id, principalId, computedRoleDefinitionId)
  parent: cosmosDbAccount
  properties: {
    roleDefinitionId: computedRoleDefinitionId
    principalId: principalId
    scope: cosmosDbAccount.id
  }
}
