@description('The name of the function app that you wish to create.')
param appName string
param appPurpose string
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

param linuxFxVersion string = 'Python|3.12'

param appSettings array = []

param networkIsolation bool = false
param identityId string
param principalId string
param clientId string

@description('The language worker runtime to load in the function app.')
param runtime string = 'python'
param aoaiEndpoint string
param storageAccountName string
param appConfigName string
param hostingPlanName string
param applicationInsightsName string
param virtualNetworkSubnetId string
param funcStorageName string
var functionAppName = appName
var functionWorkerRuntime = runtime


var openaiApiVersion = '2024-05-01-preview'
var openaiApiBase = aoaiEndpoint
var openaiModel = 'gpt-4o'

resource hostingPlan 'Microsoft.Web/serverfarms@2024-04-01' existing = {
  name: hostingPlanName
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
      '${identityId}': {}
    }
  }
  tags: tags
  properties: {
    serverFarmId: hostingPlan.id
    publicNetworkAccess: 'Enabled'  //this stays enabled even if network isolation is set to true
    virtualNetworkSubnetId: networkIsolation ? virtualNetworkSubnetId : null
    siteConfig: {
      cors: {allowedOrigins: ['https://ms.portal.azure.com', 'https://portal.azure.com'] }
      alwaysOn: true
      publicNetworkAccess: networkIsolation ? null : 'Enabled'
      ipSecurityRestrictionsDefaultAction : networkIsolation ? 'Deny' : 'Allow'
      ipSecurityRestrictions: networkIsolation ? [
        {
          ipAddress: 'AzureCloud'
          tag: 'ServiceTag'
          action: 'Allow'
          priority: 100
          name: 'AllowAzureCloud'
          headers: {
          }
        }
      ] : null
      appSettings: concat(appSettings, [
        {
          name: 'AZURE_CLIENT_ID'
          value: clientId
        }
        {
          name: 'AZURE_TENANT_ID'
          value: subscription().tenantId
        }
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
          value: clientId
        }
        {
          name: 'AzureWebJobsStorage__accountName'
          value: funcStorageName
        }
        {
          name: 'DataStorage__clientId'
          value: clientId
        }
        {
          name: 'DataStorage__accountName'
          value: storageAccountName
        }
        {
          name: 'DataStorage__credential'
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
        networkIsolation ? {
          name: 'WEBSITE_VNET_ROUTE_ALL'
          value: '1'
        } : {
          name: 'WEBSITE_VNET_ROUTE_ALL'
          value: '0'
        }
        networkIsolation ? {
          name: 'WEBSITE_DNS_SERVER'
          value: '168.63.129.16'
        } : {
          name: 'WEBSITE_DNS_SERVER'
          value: ''
        }
        {
          name: 'WEBSITE_HTTPLOGGING_RETENTION_DAYS'
          value: '7'
        }
      ], appPurpose == 'processing' ? [
        {
          name: 'AzureWebJobsFeatureFlags'
          value: 'EnableWorkerIndexing'
        }
      ] : [])
      ftpsState: 'FtpsOnly'
      linuxFxVersion: linuxFxVersion
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
output identityPrincipalId string = principalId
output location string = functionApp.location
output funcStorageName string = funcStorageName
output openaiApiVersion string = openaiApiVersion
output openaiApiBase string = openaiApiBase
output openaiModel string = openaiModel
output functionWorkerRuntime string = functionWorkerRuntime
output hostingPlanName string = hostingPlan.name
output hostingPlanId string = hostingPlan.id
