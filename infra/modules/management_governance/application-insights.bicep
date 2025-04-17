@description('Name of the resource.')
param name string
@description('Location to deploy the resource. Defaults to the location of the resource group.')
param location string = resourceGroup().location
@description('Tags for the resource.')
param tags object = {}

param appInsightsReuse bool
param logAnalyticsReuse bool
param existingAppInsightsResourceGroupName string

param publicNetworkAccessForIngestion string = 'Enabled'
param publicNetworkAccessForQuery string = 'Enabled'

param suffix string

@description('Name for the Log Analytics Workspace resource associated with the Application Insights instance.')
param logAnalyticsWorkspaceId string

var abbrs = loadJsonContent('../../abbreviations.json')

resource existinglogAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = {
  name: '${abbrs.managementGovernance.logAnalyticsWorkspace}${suffix}'
}

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = if ( !appInsightsReuse && empty(logAnalyticsWorkspaceId) ) {
  name: '${abbrs.managementGovernance.logAnalyticsWorkspace}${suffix}'
  location: location
  properties: {
    sku: {
      name: 'pergb2018'
    }
    retentionInDays: 30
  }
}

// If reusing an existing App Insights resource, reference it (assumed to already be workspace‐based)
resource existingApplicationInsights 'Microsoft.Insights/components@2020-02-02' existing = if (appInsightsReuse) {
  scope: resourceGroup(existingAppInsightsResourceGroupName)
  name: name
}

resource applicationInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: name
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: appInsightsReuse ? existinglogAnalyticsWorkspace.id : logAnalyticsWorkspace.id
    publicNetworkAccessForIngestion: publicNetworkAccessForIngestion
    publicNetworkAccessForQuery: publicNetworkAccessForQuery
  }
}

@description('ID for the deployed Application Insights resource.')
output id string = appInsightsReuse ? existingApplicationInsights.id : applicationInsights.id
@description('Name for the deployed Application Insights resource.')
output name string = appInsightsReuse ? existingApplicationInsights.name : applicationInsights.name
@description('Instrumentation Key for the deployed Application Insights resource.')
output instrumentationKey string = appInsightsReuse ? existingApplicationInsights.properties.InstrumentationKey : applicationInsights.properties.InstrumentationKey
@description('Connection string for the deployed Application Insights resource.')
output connectionString string = appInsightsReuse ? existingApplicationInsights.properties.ConnectionString : applicationInsights.properties.ConnectionString
