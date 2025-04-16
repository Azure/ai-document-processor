@description('The name of the function app that you wish to create.')
param appName string

@description('Storage Account type')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
])
param storageAccountType string = 'Standard_LRS'

@description('Location for all resources.')
param location string

@description('Tags.')
param tags object

param staticWebAppUrl string

@description('The language worker runtime to load in the function app.')
param runtime string = 'python'
param aoaiEndpoint string
param storageAccountName string
param appConfigName string
param hostingPlanName string
param applicationInsightsName string

var functionAppName = appName
var functionWorkerRuntime = runtime

var blobEndpoint = 'https://${storageAccountName}.blob.${environment().suffixes.storage}'
var promptFile = 'prompts.yaml'

var openaiApiVersion = '2024-05-01-preview'
var openaiApiBase = aoaiEndpoint
var openaiModel = 'gpt-4o'

resource uaiAppConfig 'Microsoft.ManagedIdentity/userAssignedIdentities@2024-11-30' = {
  location: location
  name: 'uai-${functionAppName}'
}

resource hostingPlan 'Microsoft.Web/serverfarms@2024-04-01' existing = {
  name: hostingPlanName
}

//get existing storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' existing = {
  name: storageAccountName
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

resource functionApp 'Microsoft.Web/sites@2024-04-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uaiAppConfig.id}': {}
    }
  }
  tags: tags
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
      cors: {allowedOrigins: ['https://ms.portal.azure.com', 'https://portal.azure.com', '${staticWebAppUrl}'] }
      alwaysOn: true
      connectionStrings: [
        /*
        {
          name: 'AzureWebJobsStorage'
          connectionString: concat('DefaultEndpointsProtocol=https;AccountName=', storageAccountName, ';AccountKey=', listKeys(storageAccountName, '2024-01-01').keys[0].value, ';EndpointSuffix=', environment().suffixes.storage)
          type: 'Custom'
        }
          */
      ]
      appSettings: [
        {
          name: 'AZURE_CLIENT_ID'
          value: uaiAppConfig.properties.clientId
        }
        {
          name: 'AZURE_TENANT_ID'
          value: subscription().tenantId
        }
        /*
        {
          name: 'AzureWebJobsStorage'
          value: concat('DefaultEndpointsProtocol=https;AccountName=', storageAccountName, ';AccountKey=', storageAccount.listkeys('2024-01-01').keys[0].value, ';EndpointSuffix=', environment().suffixes.storage)
        }
        {
          name: 'AzureWebJobsSecretStorageType'
          value: 'files'
        }
        */
        {
          name:'allow_environment_variables'
          value: 'true'
        }
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
        }
        {
          name: 'AzureWebJobsStorage__clientId'
          value: uaiAppConfig.properties.clientId
        }
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccountName
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'ApplicationInsights__InstrumentationKey'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionWorkerRuntime
        }
        
        {
          name: 'ENABLE_ORYX_BUILD'
          value: 'true'
        }
        {
          name: 'SCM_DO_BUILD_DURING_DEPLOYMENT'
          value: 'true'
        }
        {
          name: 'APP_CONFIGURATION_URI'
          value: concat('https://', appConfigName, '.azconfig.io')
        }
      ]
      ftpsState: 'FtpsOnly'
      linuxFxVersion: 'Python|3.11'
      minTlsVersion: '1.2'
    }  
    httpsOnly: true
  }
}

resource authConfig 'Microsoft.Web/sites/config@2024-04-01' = {
  parent: functionApp
  name: 'authsettingsV2' 
  properties: {
    globalValidation: {
      requireAuthentication: false  // ✅ Disables authentication (allows anonymous access)
    }
    platform: {
      enabled: false  // ✅ Ensures platform authentication is disabled
    }
  }
}

output id string = functionApp.id
output name string = functionApp.name
output uri string = 'https://${functionApp.properties.defaultHostName}'
//output identityPrincipalId string = functionApp.identity.principalId
output identityPrincipalId string = uaiAppConfig.properties.principalId
output location string = functionApp.location
output storageAccountName string = storageAccountName
output blobEndpoint string = blobEndpoint
output promptFile string = promptFile
output openaiApiVersion string = openaiApiVersion
output openaiApiBase string = openaiApiBase
output openaiModel string = openaiModel
output functionWorkerRuntime string = functionWorkerRuntime
output hostingPlanName string = hostingPlan.name
output hostingPlanId string = hostingPlan.id
