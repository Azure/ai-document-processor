targetScope = 'resourceGroup'

@description('Object id of the principal to assign the role to (user, service principal, group).')
param principalId string = '11db3526-9f5a-43c6-b3e4-bde7f47016e9'
var roles = loadJsonContent('./roles.json')

@description('Principal type: User, Group, ServicePrincipal, etc.')
param principalType string = 'User'

module keyVaultAdmin './modules/rbac/role.bicep' = {
  name: 'testKeyVaultAdmin'
  params: {
    principalId: principalId
    roleDefinitionId: roles.security.keyVaultAdministrator
    principalType: principalType
  }
}
