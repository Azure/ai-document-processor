var tenantId = tenant().tenantId
param location string = 'eastus'
param appInsightsLocation string = 'eastus'
param environmentName string = 'dev'
param functionAppName string = 'functionapp-${environmentName}-${uniqueString(resourceGroup().id)}'
param staticWebAppName string = 'static-${environmentName}-${uniqueString(resourceGroup().id)}'
param userPrincipalId string

@description('Forked Git repository URL for the Static Web App')
param user_gh_url string


var fileStorageName = 'storage${uniqueString(resourceGroup().id)}'


// module fileStorage './modules/fileStorage.bicep' = {
//   name: 'fileStorageModule'
//   params: {
//     storageAccountName: fileStorageName
//     location: location
//   }
// }

// module searchService './modules/searchService.bicep' = {
//   name: 'searchServiceModule'
//   params: {
//     searchServiceName: 'searchservice-${uniqueString(resourceGroup().id)}'
//   }
// }

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
  params: {
    location: location
    name: 'aoai-${uniqueString(resourceGroup().id)}'
  }
}


// Pass resources to functionApp module
module functionApp './modules/functionApp.bicep' = {
  name: 'functionAppModule'
  params: {
    appName: functionAppName
    location: location
    appInsightsLocation: appInsightsLocation
    fileStorageName: fileStorageName
    aoaiEndpoint: aoai.outputs.AOAI_ENDPOINT
  }
}


module staticWebApp './modules/staticWebapp.bicep' = {
  name: 'staticWebAppModule'
  params: {
    staticWebAppName: staticWebAppName
    functionAppResourceId: functionApp.outputs.id
    user_gh_url: user_gh_url
  }
}

module functionStorageAccess './modules/rbac/blob-dataowner.bicep' = {
  name: 'functionstorage-access'
  scope: resourceGroup()
  params: {
    resourceName: functionApp.outputs.storageAccountName
    principalID: functionApp.outputs.identityPrincipalId
  }
}

module functionQueueAccess './modules/rbac/blob-queue-contributor.bicep' = {
  name: 'functionqueue-access'
  scope: resourceGroup()
  params: {
    resourceName: functionApp.outputs.storageAccountName
    principalId: functionApp.outputs.identityPrincipalId
  }
}

// module fileStorageAccess './modules/rbac/blob-contributor.bicep' = {
//   name: 'blobstorage-access'
//   scope: resourceGroup()
//   params: {
//     resourceName: fileStorage.outputs.name
//     principalId: functionApp.outputs.identityPrincipalId
//   }
// }


resource functionAppContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (userPrincipalId != '') {
  name: guid(subscription().subscriptionId, resourceGroup().name, functionApp.name, 'contributor')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor Role ID
    principalId: userPrincipalId
    principalType: 'User'  // Your User Object ID
  }
}

resource aiServicesOaiUser 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
  name: guid(resourceGroup().id, aoai.name)
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908')
    principalId: functionApp.outputs.identityPrincipalId
    principalType: 'ServicePrincipal'
  }
}

output RESOURCE_GROUP string = resourceGroup().name
output FUNCTION_APP_NAME string = functionApp.outputs.name
output AZURE_STORAGE_ACCOUNT string = functionApp.outputs.storageAccountName
output FUNCTION_URL string = functionApp.outputs.uri
output BLOB_ENDPOINT string = functionApp.outputs.blobEndpoint
output PROMPT_FILE string = functionApp.outputs.promptFile
output OPENAI_API_VERSION string = functionApp.outputs.openaiApiVersion
output OPENAI_API_BASE string = functionApp.outputs.openaiApiBase
output OPENAI_MODEL string = functionApp.outputs.openaiModel
output FUNCTIONS_WORKER_RUNTIME string = functionApp.outputs.functionWorkerRuntime
