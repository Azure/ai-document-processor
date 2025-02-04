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

@description('Location for Application Insights')
param appInsightsLocation string

@description('The language worker runtime to load in the function app.')
param runtime string = 'python'
param aoaiEndpoint string
param storageAccountName string

var functionAppName = appName
var hostingPlanName = appName
var applicationInsightsName = appName
var functionWorkerRuntime = runtime

var blobEndpoint = 'https://${storageAccountName}.blob.${environment().suffixes.storage}'
var promptFile = 'prompts.yaml'

var openaiApiVersion = '2024-05-01-preview'
var openaiApiBase = aoaiEndpoint
var openaiModel = 'gpt-4o'

resource storageAccount 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: storageAccountType
  }
  kind: 'Storage'
  properties: {
    // allowBlobPublicAccess: true
  }
}

resource hostingPlan 'Microsoft.Web/serverfarms@2021-03-01' = {
  name: hostingPlanName
  location: location
  sku: {
    name: 'P0v3'
    capacity: 1
  }
  properties: {
    reserved: true
  }
  kind: 'linux'
}

resource functionApp 'Microsoft.Web/sites@2021-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp,linux'
  identity: {
    type: 'SystemAssigned'
  }
  tags: {
    'azd-service-name': 'myfunctionapp'
  }
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
      cors: {allowedOrigins: ['https://ms.portal.azure.com', 'https://portal.azure.com'] }
      alwaysOn: true
      appSettings: [
        {
          name: 'AzureWebJobsStorage__accountName'
          value: storageAccount.name
        }
        {
          name: 'AzureWebJobsStorage__credential'
          value: 'managedidentity'
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
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionWorkerRuntime
        }
        {
          name: 'BLOB_ENDPOINT'
          value: blobEndpoint
        }
        {
          name: 'PROMPT_FILE'
          value: promptFile
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
          name: 'OPENAI_API_VERSION'
          value: openaiApiVersion
        }
        {
          name: 'OPENAI_API_BASE'
          value: aoaiEndpoint
        }
        {
          name: 'OPENAI_MODEL'
          value: openaiModel
        }
      ]
      ftpsState: 'FtpsOnly'
      linuxFxVersion: 'Python|3.11'
      minTlsVersion: '1.2'
    }  
    httpsOnly: true
  }
}

resource authConfig 'Microsoft.Web/sites/config@2022-03-01' = {
  parent: functionApp
  name: 'authsettingsV2'  // ✅ Correct way to configure authentication
  properties: {
    globalValidation: {
      requireAuthentication: false  // ✅ Disables authentication (allows anonymous access)
    }
    platform: {
      enabled: false  // ✅ Ensures platform authentication is disabled
    }
  }
}


resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: applicationInsightsName
  location: appInsightsLocation
  kind: 'web'
  properties: {
    Application_Type: 'web'
    Request_Source: 'rest'
  }
}

// Blob Services 
resource blobService 'Microsoft.Storage/storageAccounts/blobServices@2022-09-01' = {
  parent: storageAccount
  name: 'default'
}

// Storage Containers
resource bronzeContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  parent: blobService
  name: 'bronze'
  properties: {
    publicAccess: 'None'
  }
}

resource silverContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  parent: blobService
  name: 'silver'
  properties: {
    publicAccess: 'None'
  }
}

resource goldContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  parent: blobService
  name: 'gold'
  properties: {
    publicAccess: 'None'
  }
}

resource promptContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2022-09-01' = {
  parent: blobService
  name: 'prompts'
  properties: {
    publicAccess: 'None'
  }
}

output id string = functionApp.id
output name string = functionApp.name
output uri string = 'https://${functionApp.properties.defaultHostName}'
output identityPrincipalId string = functionApp.identity.principalId
output location string = functionApp.location
output storageAccountName string = storageAccount.name
output blobEndpoint string = blobEndpoint
output promptFile string = promptFile
output openaiApiVersion string = openaiApiVersion
output openaiApiBase string = openaiApiBase
output openaiModel string = openaiModel
output functionWorkerRuntime string = functionWorkerRuntime
