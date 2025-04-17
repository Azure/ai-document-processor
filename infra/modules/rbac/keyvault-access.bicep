param principalId string
param roleDefinitionId string
param principalType string
param resourceName string

resource keyVault 'Microsoft.KeyVault/vaults@2022-07-01' existing = {
  name: resourceName
}

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
    name: guid(keyVault.id, principalId, roleDefinitionId)
    scope: keyVault
    properties: {
      principalId: principalId
      roleDefinitionId: roleDefinitionId
      principalType: principalType
    }
  }
