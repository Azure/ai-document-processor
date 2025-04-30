/** Inputs **/
@description('Location for all resources')
param name string

@description('MSI id for resource.')
param identityId string?

@description('Location for all resources')
param location string

@description('Resource suffix for all resources')
param resourceToken string

@description('Tags for all resources')
param tags object

@description('Keys to add to App Configuration')
param appSettings array

@description('Secret Keys to add to App Configuration')
param secureAppSettings array

@description('Whether to enable public network access. Defaults to Enabled.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'

@description('App Configuration')
resource main 'Microsoft.AppConfiguration/configurationStores@2024-05-01' = {
  identity: {
    type: identityId == null ? 'SystemAssigned' : 'UserAssigned'
    userAssignedIdentities: identityId == null
      ? null
      : {
          '${identityId}': {}
        }
  }
  location: location
  name: name
  properties: {
    disableLocalAuth: false
    enablePurgeProtection: true
    encryption: {}
    publicNetworkAccess: publicNetworkAccess
    softDeleteRetentionInDays: 7
  }
  sku: {
    name: 'standard'
  }
  tags: tags
}

resource keyValue 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-05-01' = [for (config, i) in appSettings: {
  parent: main
  name: config.name
  properties: {
    contentType: ''
    tags: {}
    value: config.value
  }
}
]

resource secureKeyValue 'Microsoft.AppConfiguration/configurationStores/keyValues@2024-05-01' = [for (config, i) in secureAppSettings: {
  parent: main
  name: config.name
  properties: {
    contentType: 'application/vnd.microsoft.appconfig.keyvaultref+json;charset=utf-8'
    tags: {}
    value: config.value
  }
}
]

@description('App Configuration resource Id')
output id string = main.id
@description('App Configuration resource Name')
output name string = main.name
@description('App Configuration resource EndPoint')
output endpoint string = main.properties.endpoint
