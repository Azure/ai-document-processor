param principalIds array
param resourceName string
param roleDefinitionGuid string = '00000000-0000-0000-0000-000000000002' // Cosmos DB Built-in Data Contributor

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2021-04-15' existing = {
  name: resourceName
}

var computedRoleDefinitionId = resourceId(resourceGroup().name, 'Microsoft.DocumentDB/databaseAccounts/sqlRoleDefinitions', resourceName, roleDefinitionGuid)

resource roleAssignment 'Microsoft.DocumentDB/databaseAccounts/sqlRoleAssignments@2024-05-15' = [for principalId in principalIds: {
  name: guid(cosmosDbAccount.id, principalId, computedRoleDefinitionId)
  parent: cosmosDbAccount
  properties: {
    roleDefinitionId: computedRoleDefinitionId
    principalId: principalId
    scope: cosmosDbAccount.id
  }
}]
