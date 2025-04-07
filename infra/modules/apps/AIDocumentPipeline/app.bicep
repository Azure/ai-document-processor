targetScope = 'resourceGroup'

@minLength(1)
@maxLength(48)
@description('Name of the workload which is used to generate a short unique hash used in all resources.')
param workloadName string

@minLength(1)
@description('Primary location for all resources.')
param location string

@description('AppConfiguration name')
param appConfigurationName string

@description('Tags for all resources.')
param tags object = {
  WorkloadName: workloadName
  Environment: 'Dev'
  ApplicationName: applicationName
}

@description('Name of the application.')
param applicationName string = 'ai-document-pipeline'

@description('Name of the container image.')
param containerImageName string

@description('Name of the Azure OpenAI completion model for the application. Default is gpt-4o.')
param chatModelDeployment string = 'gpt-4o'

var abbrs = loadJsonContent('../../abbreviations.json')
var roles = loadJsonContent('../../roles.json')
//var resourceToken = toLower(uniqueString(subscription().id, workloadName, location))
var resourceToken = toLower(uniqueString(subscription().id, workloadName, location))

var containerRegistryName = '${abbrs.containers.containerRegistry}${resourceToken}'
resource containerRegistryRef 'Microsoft.ContainerRegistry/registries@2023-11-01-preview' existing = {
  name: containerRegistryName
}

var applicationInsightsName = '${abbrs.managementGovernance.applicationInsights}${resourceToken}'
resource applicationInsightsRef 'Microsoft.Insights/components@2020-02-02' existing = {
  name: applicationInsightsName
}

var storageAccountName = '${abbrs.storage.storageAccount}${resourceToken}'
resource storageAccountRef 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

var aiServicesName = '${abbrs.ai.aiServices}${resourceToken}'
resource aiServicesRef 'Microsoft.CognitiveServices/accounts@2024-04-01-preview' existing = {
  name: aiServicesName
}

var containerAppsEnvironmentName = '${abbrs.containers.containerAppsEnvironment}${resourceToken}'
resource containerAppsEnvironmentRef 'Microsoft.App/managedEnvironments@2024-03-01' existing = {
  name: containerAppsEnvironmentName
}

var functionsWebJobStorageVariableName = 'AzureWebJobsStorage'
var documentsConnectionStringVariableName = 'AZURE_STORAGE_QUEUES_CONNECTION_STRING'
var applicationInsightsConnectionStringSecretName = 'applicationinsightsconnectionstring'

var applicationManagedIdentityName = '${abbrs.security.managedIdentity}${abbrs.containers.containerAppsEnvironment}${resourceToken}'
module applicationManagedIdentity '../../security/managed-identity.bicep' = {
  name: applicationManagedIdentityName
  params: {
    name: applicationManagedIdentityName
    location: location
    tags: union(tags, {})
  }
}

resource acrPullRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: roles.containers.acrPull
}

module containerRegistryIdentityRoleAssignment '../../security/resource-role-assignment.json' = {
  name: 'containerRegistryIdentityRoleAssignment'
  params: {
    resourceId: containerRegistryRef.id
    roleAssignments: [
      {
        principalId: applicationManagedIdentity.outputs.principalId
        roleDefinitionId: acrPullRole.id
        principalType: 'ServicePrincipal'
      }
    ]
  }
}

// Required RBAC roles for Azure Functions to access the storage account
// https://learn.microsoft.com/en-us/azure/azure-functions/functions-reference?tabs=blob&pivots=programming-language-python#connecting-to-host-storage-with-an-identity
resource storageAccountContributorRole 'Microsoft.Authorization/roleDefinitions@2022-05-01-preview' existing = {
  name: roles.storage.storageAccountContributor
}

resource storageBlobDataContributorRole 'Microsoft.Authorization/roleDefinitions@2022-05-01-preview' existing = {
  name: roles.storage.storageBlobDataContributor
}

resource storageBlobDataOwnerRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: roles.storage.storageBlobDataOwner
}

resource storageFileDataPrivilegedContributorRole 'Microsoft.Authorization/roleDefinitions@2022-05-01-preview' existing = {
  name: roles.storage.storageFileDataPrivilegedContributor
}

resource storageTableDataContributorRole 'Microsoft.Authorization/roleDefinitions@2022-05-01-preview' existing = {
  name: roles.storage.storageTableDataContributor
}

resource storageQueueDataContributorRole 'Microsoft.Authorization/roleDefinitions@2022-04-01' existing = {
  name: roles.storage.storageQueueDataContributor
}

module storageAccountIdentityRoleAssignment '../../security/resource-role-assignment.json' = {
  name: 'storageAccountIdentityRoleAssignment'
  params: {
    resourceId: storageAccountRef.id
    roleAssignments: [
      {
        principalId: applicationManagedIdentity.outputs.principalId
        roleDefinitionId: storageAccountContributorRole.id
        principalType: 'ServicePrincipal'
      }
      {
        principalId: applicationManagedIdentity.outputs.principalId
        roleDefinitionId: storageBlobDataContributorRole.id
        principalType: 'ServicePrincipal'
      }
      {
        principalId: applicationManagedIdentity.outputs.principalId
        roleDefinitionId: storageBlobDataOwnerRole.id
        principalType: 'ServicePrincipal'
      }
      {
        principalId: applicationManagedIdentity.outputs.principalId
        roleDefinitionId: storageFileDataPrivilegedContributorRole.id
        principalType: 'ServicePrincipal'
      }
      {
        principalId: applicationManagedIdentity.outputs.principalId
        roleDefinitionId: storageTableDataContributorRole.id
        principalType: 'ServicePrincipal'
      }
      {
        principalId: applicationManagedIdentity.outputs.principalId
        roleDefinitionId: storageQueueDataContributorRole.id
        principalType: 'ServicePrincipal'
      }
    ]
  }
}

resource cognitiveServicesUserRole 'Microsoft.Authorization/roleDefinitions@2022-05-01-preview' existing = {
  name: roles.ai.cognitiveServicesUser
}

resource cognitiveServicesOpenAIUserRole 'Microsoft.Authorization/roleDefinitions@2022-05-01-preview' existing = {
  name: roles.ai.cognitiveServicesOpenAIUser
}

module aiServicesIdentityRoleAssignment '../../security/resource-role-assignment.json' = {
  name: 'aiServicesIdentityRoleAssignment'
  params: {
    resourceId: aiServicesRef.id
    roleAssignments: [
      {
        principalId: applicationManagedIdentity.outputs.principalId
        roleDefinitionId: cognitiveServicesUserRole.id
        principalType: 'ServicePrincipal'
      }
      {
        principalId: applicationManagedIdentity.outputs.principalId
        roleDefinitionId: cognitiveServicesOpenAIUserRole.id
        principalType: 'ServicePrincipal'
      }
    ]
  }
}

var documentsQueueName = 'documents'
module documentsQueue '../../storage/storage-queue.bicep' = {
  name: '${abbrs.storage.storageAccount}${resourceToken}-${documentsQueueName}'
  params: {
    name: documentsQueueName
    storageAccountName: storageAccountRef.name
  }
}

module containerApp '../../containers/container-app.bicep' = {
  name: '${abbrs.containers.containerApp}${resourceToken}'
  params: {
    name: '${abbrs.containers.containerApp}${resourceToken}'
    location: location
    tags: union(tags, { App: 'ai-document-pipeline' })
    containerAppsEnvironmentId: containerAppsEnvironmentRef.id
    containerAppIdentityId: applicationManagedIdentity.outputs.id
    imageInContainerRegistry: true
    containerRegistryName: containerRegistryRef.name
    containerImageName: containerImageName
    containerIngress: {
      external: true
      targetPort: 80
      transport: 'auto'
      allowInsecure: false
    }
    containerScale: {
      minReplicas: 1
      maxReplicas: 3
      rules: [
        {
          name: 'http'
          http: {
            metadata: {
              concurrentRequests: '20'
            }
          }
        }
      ]
    }
    secrets: [
      {
        name: applicationInsightsConnectionStringSecretName
        value: applicationInsightsRef.properties.ConnectionString
      }
    ]
    environmentVariables: [
      {
        name: 'AzureWebJobsFeatureFlags'
        value: 'EnableWorkerIndexing'
      }
      {
        name: 'FUNCTIONS_EXTENSION_VERSION'
        value: '~4'
      }
      {
        name: 'FUNCTIONS_WORKER_RUNTIME'
        value: 'python'
      }
      {
        name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
        secretRef: applicationInsightsConnectionStringSecretName
      }
      {
        name: 'AZURE_APPCONFIG_URL'
        value: concat('https://', appConfigurationName, '.azconfig.io')
      }
      {
        name: '${functionsWebJobStorageVariableName}__accountName'
        value: storageAccountRef.name
      }
      {
        name: '${functionsWebJobStorageVariableName}__credential'
        value: 'managedidentity'
      }
      {
        name: '${functionsWebJobStorageVariableName}__clientId'
        value: applicationManagedIdentity.outputs.clientId
      }
      {
        name: 'AZURE_CLIENT_ID'
        value: applicationManagedIdentity.outputs.clientId
      }
      {
        name: 'AZURE_AISERVICES_ENDPOINT'
        value: aiServicesRef.properties.endpoint
      }
      {
        name: 'AZURE_OPENAI_ENDPOINT'
        value: aiServicesRef.properties.endpoint
      }
      {
        name: 'AZURE_OPENAI_CHAT_DEPLOYMENT'
        value: chatModelDeployment
      }
      {
        name: 'AZURE_STORAGE_ACCOUNT'
        value: storageAccountRef.name
      }
      {
        name: '${documentsConnectionStringVariableName}__accountName'
        value: storageAccountRef.name
      }
      {
        name: '${documentsConnectionStringVariableName}__credential'
        value: 'managedidentity'
      }
      {
        name: '${documentsConnectionStringVariableName}__clientId'
        value: applicationManagedIdentity.outputs.clientId
      }
      {
        name: 'WEBSITE_HOSTNAME'
        value: 'localhost'
      }
    ]
  }
}

output appInfo object = {
  id: containerApp.outputs.id
  name: containerApp.outputs.name
  fqdn: containerApp.outputs.fqdn
  url: containerApp.outputs.url
  latestRevisionFqdn: containerApp.outputs.latestRevisionFqdn
  latestRevisionUrl: containerApp.outputs.latestRevisionUrl
}
