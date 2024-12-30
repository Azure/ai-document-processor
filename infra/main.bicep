var tenantId = tenant().tenantId
param location string = 'eastus'
param appInsightsLocation string = 'eastus'
param environmentName string = 'dev'
param functionAppName string = 'functionapp-${environmentName}-${uniqueString(resourceGroup().id)}'

// Pass resources to functionApp module
module functionApp './modules/functionApp.bicep' = {
  name: 'functionAppModule'
  params: {
    appName: functionAppName
    location: location
    appInsightsLocation: appInsightsLocation
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
