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
param suffix string = uniqueString('${location}${resourceGroup().id}')
// Environment name. This is automatically set by the 'azd' tool.
@description('Environment name used as a tag for all resources. This is directly mapped to the azd-environment.')
// param environmentName string = 'dev'
param processingFunctionAppName string = 'processing-${suffix}'
param webBackendFunctionAppName string = 'webbackend-${suffix}'
param staticWebAppName string = 'static-${suffix}'
var tenantId = tenant().tenantId
param storageAccountName string = 'azfn${suffix}'
param keyVaultName string = 'keyvault-${suffix}'
param aoaiName string = 'aoai-${suffix}'
param aiServicesName string = 'aiServices-${suffix}'
param cosmosAccountName string = 'cosmos-${suffix}'
param promptsContainer string = 'promptscontainer'
param configContainerName string = 'config'
param cosmosDatabaseName string = 'openaiPromptsDB'
param aiMultiServicesName string = 'aimultiservices-${suffix}'
@description('Deploy a Static Web App front end? Set to true to deploy, false to skip.')
param deployStaticWebApp bool

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

// 4. Cosmos DB
module cosmos './modules/cosmos.bicep' = {
  name: 'cosmosModule'
  params: {
    location: location
    accountName: cosmosAccountName
    databaseName: cosmosDatabaseName
    containerName: promptsContainer
    configContainerName: configContainerName
  }
}

// File Processing Function App
module processingFunctionApp './modules/functionApp.bicep' = {
  name: 'processingFunctionAppModule'
  params: {
    appName: processingFunctionAppName
    appPurpose: 'processing'
    location: location
    storageAccountName: storageAccountName
    aoaiEndpoint: aoai.outputs.AOAI_ENDPOINT
    cosmosName: cosmos.outputs.accountName
    aiMultiServicesEndpoint: aiMultiServices.outputs.aiMultiServicesEndpoint
  }
}

// Web Backend Function App
module webBackendFunctionApp './modules/functionApp.bicep' = {
  name: 'webBackendFunctionAppModule'
  params: {
    appName: webBackendFunctionAppName
    appPurpose: 'webbackend'
    location: location
    storageAccountName: storageAccountName
    aoaiEndpoint: aoai.outputs.AOAI_ENDPOINT
    cosmosName: cosmos.outputs.accountName
    aiMultiServicesEndpoint: aiMultiServices.outputs.aiMultiServicesEndpoint
  }
}

// 5. Static Web App
module staticWebApp './modules/staticWebapp.bicep' = if (deployStaticWebApp) {
  name: 'staticWebAppModule'
  params: {
    staticWebAppName: staticWebAppName
    functionAppResourceId: webBackendFunctionApp.outputs.id // Updated to use web backend app
    user_gh_url: user_gh_url
    location: location
    cosmosId: cosmos.outputs.cosmosResourceId
  }
}

// 6. Azure AI Multi Services
module aiMultiServices './modules/aimultiservices.bicep' = {
  name: 'aiMultiServicesModule'
  params: {
    aiMultiServicesName: aiMultiServicesName
    location: location
  }
}

// Invoke the role assignment module for Storage Queue Data Contributor
module cosmosContributor './modules/rbac/cosmos-contributor.bicep' = {
  name: 'cosmosContributorModule'
  scope: resourceGroup() // Role assignment applies to the storage account
  params: {
    principalId: webBackendFunctionApp.outputs.identityPrincipalId
    resourceName: cosmos.outputs.accountName
  }
}

// Invoke the role assignment module for Storage Queue Data Contributor
module cosmosContributorUser './modules/rbac/cosmos-contributor.bicep' = {
  name: 'cosmosContributorUserModule'
  scope: resourceGroup() // Role assignment applies to the storage account
  params: {
    principalId: userPrincipalId
    resourceName: cosmos.outputs.accountName
  }
}

// Invoke the role assignment module for Storage Blob Data Contributor
module blobStorageDataContributor './modules/rbac/blob-contributor.bicep' = {
  name: 'blobRoleAssignmentModule'
  scope: resourceGroup() // Role assignment applies to the storage account
  params: {
    principalIds: [webBackendFunctionApp.outputs.identityPrincipalId, processingFunctionApp.outputs.identityPrincipalId]
    resourceName: webBackendFunctionApp.outputs.storageAccountName
  }
}

// Invoke the role assignment module for Storage Queue Data Contributor
module blobQueueContributor './modules/rbac/blob-queue-contributor.bicep' = {
  name: 'blobQueueAssignmentModule'
  scope: resourceGroup() // Role assignment applies to the storage account
  params: {
    principalIds: [webBackendFunctionApp.outputs.identityPrincipalId, processingFunctionApp.outputs.identityPrincipalId]
    resourceName: webBackendFunctionApp.outputs.storageAccountName
  }
}

// Invoke the role assignment module for Storage Queue Data Contributor
module aiServicesOpenAIUser './modules/rbac/cogservices-openai-user.bicep' = {
  name: 'aiServicesOpenAIUserModule'
  scope: resourceGroup() // Role assignment applies to the storage account
  params: {
    principalId: webBackendFunctionApp.outputs.identityPrincipalId
    resourceName: aoai.outputs.name
  }
}

// Invoke the role assignment module for Azure AI Multi Services User
module aiMultiServicesUser './modules/rbac/aiservices-user.bicep' = {
  name: 'aiMultiServicesUserModule'
  scope: resourceGroup() // Role assignment applies to the Azure Function App
  params: {
    principalId: webBackendFunctionApp.outputs.identityPrincipalId
    resourceName: aiMultiServices.outputs.aiMultiServicesName
  }
}

// Invoke the role assignment module for Storage Queue Data Contributor
module blobContributor './modules/rbac/blob-contributor.bicep' = if (userPrincipalId != '') {
  name: 'blobStorageUserAssignmentModule'
  scope: resourceGroup() // Role assignment applies to the storage account
  params: {
    principalId: userPrincipalId
    resourceName: webBackendFunctionApp.outputs.storageAccountName
    principalType: 'User'
  }
}

// Role assignments for both function apps
// Processing Function App role assignments
module processingCosmosContributor './modules/rbac/cosmos-contributor.bicep' = {
  name: 'processingCosmosContributorModule'
  scope: resourceGroup()
  params: {
    principalId: processingFunctionApp.outputs.identityPrincipalId
    resourceName: cosmos.outputs.accountName
  }
}

module processingBlobStorageDataContributor './modules/rbac/blob-contributor.bicep' = {
  name: 'processingBlobRoleAssignmentModule'
  scope: resourceGroup()
  params: {
    principalId: processingFunctionApp.outputs.identityPrincipalId
    resourceName: processingFunctionApp.outputs.storageAccountName
  }
}

// Web Backend Function App role assignments
module webBackendCosmosContributor './modules/rbac/cosmos-contributor.bicep' = {
  name: 'webBackendCosmosContributorModule'
  scope: resourceGroup()
  params: {
    principalId: webBackendFunctionApp.outputs.identityPrincipalId
    resourceName: cosmos.outputs.accountName
  }
}

output RESOURCE_GROUP string = resourceGroup().name
output FUNCTION_APP_NAME string = webBackendFunctionApp.outputs.name
output AZURE_STORAGE_ACCOUNT string = webBackendFunctionApp.outputs.storageAccountName
output FUNCTION_URL string = webBackendFunctionApp.outputs.uri
output BLOB_ENDPOINT string = webBackendFunctionApp.outputs.blobEndpoint
output PROMPT_FILE string = webBackendFunctionApp.outputs.promptFile
output OPENAI_API_VERSION string = webBackendFunctionApp.outputs.openaiApiVersion
output OPENAI_API_BASE string = webBackendFunctionApp.outputs.openaiApiBase
output OPENAI_MODEL string = webBackendFunctionApp.outputs.openaiModel
output FUNCTIONS_WORKER_RUNTIME string = webBackendFunctionApp.outputs.functionWorkerRuntime
output STATIC_WEB_APP_NAME string = deployStaticWebApp ? staticWebApp.outputs.name : '0'
output COSMOS_DB_PROMPTS_CONTAINER string = promptsContainer
output COSMOS_DB_CONFIG_CONTAINER string = configContainerName
output COSMOS_DB_PROMPTS_DB string = cosmosDatabaseName
output COSMOS_DB_ACCOUNT_NAME string = cosmos.outputs.accountName
output COSMOS_DB_URI string = 'https://${cosmosAccountName}.documents.azure.com:443/'
output AIMULTISERVICES_NAME string = aiMultiServices.outputs.aiMultiServicesName
output AIMULTISERVICES_ENDPOINT string = aiMultiServices.outputs.aiMultiServicesEndpoint
output PROCESSING_FUNCTION_APP_NAME string = processingFunctionApp.outputs.name
output PROCESSING_FUNCTION_URL string = processingFunctionApp.outputs.uri
output WEB_BACKEND_FUNCTION_APP_NAME string = webBackendFunctionApp.outputs.name
output WEB_BACKEND_FUNCTION_URL string = webBackendFunctionApp.outputs.uri
