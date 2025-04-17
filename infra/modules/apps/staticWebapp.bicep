param staticWebAppName string
param functionAppResourceId string
param user_gh_url string = ''
@allowed([
  'centralus'
  'eastus2'
  'westeurope'
  'westus2'
  'southeastasia'
])
param location string
param cosmosId string
param appConfigName string
param suffix string
param tags object

/** Resources **/
@description('User Assigned Identity for App Configuration')
resource uaiAppConfig 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  location: location
  name: 'uai-${staticWebAppName}'
  tags: tags
}

resource staticWebApp 'Microsoft.Web/staticSites@2024-04-01' = {
  name: staticWebAppName
  location: location
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${uaiAppConfig.id}': {}
    }
  }
  properties: {
    stagingEnvironmentPolicy: 'Enabled'
    allowConfigFileUpdates: true
    // When a GitHub URL is provided, include repositoryUrl, branch, and CDN status.
    repositoryUrl: user_gh_url != '' ? user_gh_url : null
    branch: user_gh_url != '' ? 'main' : null
    enterpriseGradeCdnStatus: null
    // When no GitHub URL is provided, include buildProperties.
    buildProperties: user_gh_url == '' ? {
      skipGithubActionWorkflowGeneration: true
    } : null
  }
}

resource linkedFunctionApp 'Microsoft.Web/staticSites/linkedBackends@2024-04-01' = {
  parent: staticWebApp
  name: 'backend1'
  properties: {
    backendResourceId: functionAppResourceId
    region: location
  }
}

// Link the Cosmos DB to the static web app
resource dbConnection 'Microsoft.Web/staticSites/databaseConnections@2024-04-01' = {
  parent: staticWebApp
  name: 'default'  // Must be alphanumeric (e.g. "CosmosDb")
  kind: 'CosmosDb'
  properties: {
    connectionIdentity: uaiAppConfig.id
    connectionString: listConnectionStrings(cosmosId, '2021-04-15').connectionStrings[0].connectionString
    region: location
    resourceId: cosmosId
  }
}

// Now that there's only one staticWebApp resource, you can output its name directly.
output name string = staticWebApp.name
output identityPrincipalId string = uaiAppConfig.properties.principalId
output id string = staticWebApp.id
output defaultHostName string = staticWebApp.properties.defaultHostname
