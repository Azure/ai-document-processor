@description('Name of the resource.')
param name string

@description('Name for the Storage Account associated with the blob container.')
param storageAccountName string
@description('Public access level for the blob container.')
@allowed([
  'Blob'
  'Container'
  'None'
])
param publicAccess string = 'None'

resource container 'Microsoft.Storage/storageAccounts/blobServices/containers@2024-01-01' = {
  name: '${storageAccountName}/default/${name}'
  properties: {
    publicAccess: publicAccess
    metadata: {}
  }
}

@description('ID for the deployed Storage blob container resource.')
output id string = container.id
@description('Name for the deployed Storage blob container resource.')
output name string = name
