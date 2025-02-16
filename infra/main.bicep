@description('Location for the Static Web App and Azure Function App. Only the following locations are allowed: centralus, eastus2, westeurope, westus2, southeastasia')
@allowed([
  'centralus'
  'eastus2'
  'westeurope'
  'westus2'
  'southeastasia'
])
param location string

@description('Location for the Azure OpenAI account')
@allowed([
  'East US'
  'East US 2'
  'France Central'
  'Germany West Central'
  'Japan East'
  'Korea Central'
  'North Central US'
  'Norway East'
  'Poland Central'
  'South Africa North'
  'South Central US'
  'South India'
  'Southeast Asia'
  'Spain Central'
  'Sweden Central'
  'Switzerland North'
  'Switzerland West'
  'UAE North'
  'UK South'
  'West Europe'
  'West US'
  'West US 3'
])
param aoaiLocation string

@description('Forked Git repository URL for the Static Web App')
param user_gh_url string = ''
param userPrincipalId string
param functionAppName string = 'functionapp-${environmentName}-${uniqueString('${location}${resourceGroup().id}')}'
param staticWebAppName string = 'static-${environmentName}-${uniqueString('${location}${resourceGroup().id}')}'
var tenantId = tenant().tenantId
param environmentName string = 'dev'
param storageAccountName string = 'azfn${uniqueString('${location}${resourceGroup().id}')}'
param keyVaultName string = 'keyvault-${uniqueString('${location}${resourceGroup().id}')}'
param aoaiName string = 'aoai-${uniqueString(resourceGroup().id)}'
param aiServicesName string = 'aiServices-${uniqueString(resourceGroup().id)}'
param cosmosAccountName string = 'cosmos-${uniqueString(resourceGroup().id)}'

@description('Choose the deployment method: GitHubActions or SWA_CLI')
@allowed([
  'GitHubActions'
  'SWA_CLI'
])
param deploymentMethod string = 'GitHubActions'

// 1. Key Vault
module keyVault './modules/keyVault.bicep' = {
  name: 'keyVaultModule'
  params: {
    vaultName: keyVaultName
    location: location
    tenantId: tenantId
  }
}

// 2. OpenAI
module aoai './modules/aoai.bicep' = {
  name: 'aoaiModule'
  params: {
    location: aoaiLocation
    name: aoaiName
    aiServicesName: aiServicesName
  }
}

// 3. FunctionApp
module functionApp './modules/functionApp.bicep' = {
  name: 'functionAppModule'
  params: {
    appName: functionAppName
    location: location
    storageAccountName: storageAccountName
    aoaiEndpoint: aoai.outputs.AOAI_ENDPOINT
    aoaiName: aoai.outputs.name
  }
}

// 4. Cosmos DB
module cosmos './modules/cosmos.bicep' = {
  name: 'cosmosModule'
  params: {
    location: location
    accountName: cosmosAccountName
  }
}

// 5. Static Web App
module staticWebApp './modules/staticWebapp.bicep' = if (deploymentMethod == 'GitHubActions') {
  name: 'staticWebAppModule'
  params: {
    staticWebAppName: staticWebAppName
    functionAppResourceId: functionApp.outputs.id
    user_gh_url: user_gh_url
    location: location
    cosmosId: cosmos.outputs.cosmosResourceId
  }
}

module staticWebAppSWA './modules/staticWebapp.bicep' = if (deploymentMethod == 'SWA_CLI') {
  name: 'staticWebAppModuleSWA'
  params: {
    staticWebAppName: staticWebAppName
    functionAppResourceId: functionApp.outputs.id
    user_gh_url: ''
    location: location
    cosmosId: cosmos.outputs.cosmosResourceId
  }
}

// Invoke the role assignment module for Storage Queue Data Contributor
module blobContributor './modules/rbac/blob-contributor.bicep' = if (userPrincipalId != '') {
  name: 'blobStorageUserAssignmentModule'
  scope: resourceGroup() // Role assignment applies to the storage account
  params: {
    principalId: userPrincipalId
    resourceName: storageAccountName
  }
}

// module aiServicesOAIUser './modules/rbac/role.bicep' = {
//   name: 'aiServicesAssignment'
//   // scope: resource // Role assignment applies to the storage account
//   params: {
//     principalId: functionApp.outputs.identityPrincipalId
//     principalType: 'ServicePrincipal'
//     roleDefinitionId: 'a97b65f3-24c7-4388-baec-2e87135dc908'
//     resourceName: aoai.outputs.name
//   }
// }

// resource aiServicesOaiUser 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
//   name: guid(resourceGroup().id, aoai.name)
//   scope: resourceGroup()
//   properties: {
//     roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908')
//     principalId: functionApp.outputs.identityPrincipalId
//     principalType: 'ServicePrincipal'
//   }
// }

// RBAC Permissions
// module functionStorageAccess './modules/rbac/blob-dataowner.bicep' = {
//   name: 'functionstorage-access-2'
//   scope: resourceGroup()
//   params: {
//     resourceName: functionApp.outputs.storageAccountName
//     principalID: functionApp.outputs.identityPrincipalId
//   }
// }

// module functionQueueAccess './modules/rbac/blob-queue-contributor.bicep' = {
//   name: 'functionqueue-access-2'
//   scope: resourceGroup()
//   params: {
//     resourceName: functionApp.outputs.storageAccountName
//     principalId: functionApp.outputs.identityPrincipalId
//   }
// }

// resource functionAppContributorRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (userPrincipalId != '') {
//   name: guid(subscription().subscriptionId, resourceGroup().name, functionApp.name, 'contributor')
//   scope: resourceGroup()
//   properties: {
//     roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b24988ac-6180-42a0-ab88-20f7382dd24c') // Contributor Role ID
//     principalId: userPrincipalId
//     principalType: 'User'  // Your User Object ID
//   }
// }

// resource aiServicesOaiUser 'Microsoft.Authorization/roleAssignments@2020-04-01-preview' = {
//   name: guid(resourceGroup().id, aoai.name)
//   scope: resourceGroup()
//   properties: {
//     roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'a97b65f3-24c7-4388-baec-2e87135dc908')
//     principalId: functionApp.outputs.identityPrincipalId
//     principalType: 'ServicePrincipal'
//   }
// }


// // New assignment: Assign Key Vault Secrets User Role to the Function App's managed identity
// resource functionAppKeyVaultSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
//   // Create a unique name using the Key Vault id, Function App's identity, and a fixed string
//   name: guid(resourceGroup().id, keyVaultName)
//   scope: resourceGroup()
//   properties: {
//     roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6') // Key Vault Secrets User Role ID
//     principalId: functionApp.outputs.identityPrincipalId
//     principalType: 'ServicePrincipal'
//   }
// }

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
output STATIC_WEB_APP_NAME string = staticWebApp.outputs.name

resource cosmosDb 'Microsoft.DocumentDB/databaseAccounts@2023-03-15' existing = {
  name: cosmosAccountName

}

output DATABASE_CONNECTION_STRING string = cosmosDb.listConnectionStrings().connectionStrings[0].connectionString
