param staticWebAppName string = 'static-web-app'
param functionAppResourceId string
param user_gh_url string
param location string = 'eastus2'

resource staticWebApp 'Microsoft.Web/staticSites@2024-04-01' = {
  name: staticWebAppName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    repositoryUrl: user_gh_url
    branch: 'dev'
    stagingEnvironmentPolicy: 'Enabled'
    allowConfigFileUpdates: true
    provider: 'GitHub'
    enterpriseGradeCdnStatus: 'Disabled'
  }
}

resource staticWebAppBasicAuth 'Microsoft.Web/staticSites/basicAuth@2024-04-01' = {
  parent: staticWebApp
  name: 'default'
  location: location
  properties: {
    applicableEnvironmentsMode: 'SpecifiedEnvironments'
  }
}

resource linkedFunctionApp 'Microsoft.Web/staticSites/linkedBackends@2024-04-01' = {
  parent: staticWebApp
  name: 'backend1'
  location: location
  properties: {
    backendResourceId: functionAppResourceId
    region: 'eastus'
  }
}
