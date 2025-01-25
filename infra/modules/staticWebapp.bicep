param staticSites_doc_processing_static_webapp_name string = 'doc-processing-static-webapp'

resource staticSites_doc_processing_static_webapp_name_resource 'Microsoft.Web/staticSites@2024-04-01' = {
  name: staticSites_doc_processing_static_webapp_name
  location: 'East US 2'
  sku: {
    name: 'Free'
    tier: 'Free'
  }
  properties: {
    repositoryUrl: 'https://github.com/markremmey/llm-doc-processing'
    branch: 'main'
    stagingEnvironmentPolicy: 'Enabled'
    allowConfigFileUpdates: true
    provider: 'GitHub'
    enterpriseGradeCdnStatus: 'Disabled'
  }
}

resource staticSites_doc_processing_static_webapp_name_default 'Microsoft.Web/staticSites/basicAuth@2024-04-01' = {
  parent: staticSites_doc_processing_static_webapp_name_resource
  name: 'default'
  location: 'East US 2'
  properties: {
    applicableEnvironmentsMode: 'SpecifiedEnvironments'
  }
}
