var tenantId = tenant().tenantId
param location string = 'eastus'
param appInsightsLocation string = 'eastus'
param environmentName string = 'dev'
param functionAppName string = 'functionapp-${environmentName}-${uniqueString(resourceGroup().id)}'

var fileStorageName = 'storage${uniqueString(resourceGroup().id)}'

// Pass resources to functionApp module
module functionApp './modules/functionApp.bicep' = {
  name: 'functionAppModule'
  params: {
    appName: functionAppName
    location: location
    appInsightsLocation: appInsightsLocation
    fileStorageName: fileStorageName
  }
}

module fileStorage './modules/fileStorage.bicep' = {
  name: 'fileStorageModule'
  params: {
    storageAccountName: fileStorageName
    location: location
  }
}

module searchService './modules/searchService.bicep' = {
  name: 'searchServiceModule'
  params: {
    searchServiceName: 'searchservice-${uniqueString(resourceGroup().id)}'
  }
}

module keyVault './modules/keyVault.bicep' = {
  name: 'keyVaultModule'
  params: {
    vaultName: 'keyvault-${uniqueString(resourceGroup().id)}'
    location: location
    tenantId: tenantId
  }
}

module aoai './modules/aoai.bicep' = {
  name: 'aoaiModule'
}

module functionStorageAccess './modules/rbac/blob-dataowner.bicep' = {
  name: 'functionstorage-access'
  scope: resourceGroup()
  params: {
    resourceName: functionApp.outputs.storageAccountName
    principalID: functionApp.outputs.identityPrincipalId
  }
}

module fileStorageAccess './modules/rbac/blob-contributor.bicep' = {
  name: 'blobstorage-access'
  scope: resourceGroup()
  params: {
    resourceName: fileStorage.outputs.name
    principalId: functionApp.outputs.identityPrincipalId
  }
}
