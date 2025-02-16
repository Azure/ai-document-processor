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
// Environment name. This is automatically set by the 'azd' tool.
@description('Environment name used as a tag for all resources. This is directly mapped to the azd-environment.')
param environmentName string = 'dev'
param functionAppName string = 'functionapp-${environmentName}-${uniqueString('${location}${resourceGroup().id}')}'
param staticWebAppName string = 'static-${environmentName}-${uniqueString('${location}${resourceGroup().id}')}'
var tenantId = tenant().tenantId
param storageAccountName string = 'azfn${uniqueString('${location}${resourceGroup().id}')}'
param keyVaultName string = 'keyvault-${uniqueString('${location}${resourceGroup().id}')}'
param aoaiName string = 'aoai-${uniqueString(resourceGroup().id)}'
param aiServicesName string = 'aiServices-${uniqueString(resourceGroup().id)}'
param cosmosAccountName string = 'cosmos-${uniqueString(resourceGroup().id)}'

// @description('Choose the deployment method: GitHubActions or SWA_CLI')
// @allowed([
//   'GitHubActions'
//   'SWA_CLI'
// ])
// param deploymentMethod string = 'SWA_CLI'

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
module staticWebApp './modules/staticWebapp.bicep' = {
  name: 'staticWebAppModule'
  params: {
    staticWebAppName: staticWebAppName
    functionAppResourceId: functionApp.outputs.id
    user_gh_url: user_gh_url
    location: location
    cosmosId: cosmos.outputs.cosmosResourceId
  }
}


// Invoke the role assignment module for Storage Blob Data Contributor
module blobStorageDataContributor './modules/rbac/blob-contributor.bicep' = {
  name: 'blobRoleAssignmentModule'
  scope: resourceGroup() // Role assignment applies to the storage account
  params: {
    principalId: functionApp.outputs.identityPrincipalId
    resourceName: functionApp.outputs.storageAccountName
  }
}

// Invoke the role assignment module for Storage Queue Data Contributor
module blobQueueContributor './modules/rbac/blob-queue-contributor.bicep' = {
  name: 'blobQueueAssignmentModule'
  scope: resourceGroup() // Role assignment applies to the storage account
  params: {
    principalId: functionApp.outputs.identityPrincipalId
    resourceName: functionApp.outputs.storageAccountName
  }
}

// Invoke the role assignment module for Storage Queue Data Contributor
module aiServicesOpenAIUser './modules/rbac/cogservices-openai-user.bicep' = {
  name: 'aiServicesOpenAIUserModule'
  scope: resourceGroup() // Role assignment applies to the storage account
  params: {
    principalId: functionApp.outputs.identityPrincipalId
    resourceName: aoai.outputs.name
  }
}


// Invoke the role assignment module for Storage Queue Data Contributor
module blobContributor './modules/rbac/blob-contributor.bicep' = if (userPrincipalId != '') {
  name: 'blobStorageUserAssignmentModule'
  scope: resourceGroup() // Role assignment applies to the storage account
  params: {
    principalId: userPrincipalId
    resourceName: functionApp.outputs.storageAccountName
    principalType: 'User'
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
output STATIC_WEB_APP_NAME string = staticWebApp.outputs.name
