// param functionAppBase string
param vaultBase string
// param componentsFunctionAppBase string
param searchServicesBase string
param storageAccountBase string
// param workspaces_DefaultWorkspace_253f778b_553f_4871_b143_123f314c45c1_CCAN_externalid string = '/subscriptions/253f778b-553f-4871-b143-123f314c45c1/resourceGroups/DefaultResourceGroup-CCAN/providers/Microsoft.OperationalInsights/workspaces/DefaultWorkspace-253f778b-553f-4871-b143-123f314c45c1-CCAN'
// param serverfarms_ASP_functionapp_name string = 'ASP-functionapp912-a4a6'
param workspaceName string = 'DefaultWorkspace'
// param location string = 'eastus'
param tenantId string = '16b3c013-d300-468d-ac64-7eda0820b6d3'

@description('The name of the function app that you wish to create.')
param appName string = 'fnapp${uniqueString(resourceGroup().id)}'

@description('Storage Account type')
@allowed([
  'Standard_LRS'
  'Standard_GRS'
  'Standard_RAGRS'
])
param storageAccountType string = 'Standard_LRS'

@description('Location for all resources.')
param location string = resourceGroup().location

@description('Location for Application Insights')
param appInsightsLocation string

@description('The language worker runtime to load in the function app.')
@allowed([
  'node'
  'dotnet'
  'java'
])
param runtime string = 'node'

var functionAppName = appName
var hostingPlanName = appName
var applicationInsightsName = appName
var storageAccountNameFunction = '${uniqueString(resourceGroup().id)}azfunctions'
var functionWorkerRuntime = runtime


param unique_seed string = 'seed8790145'
// var functionAppName = '${functionAppBase}-${uniqueString(unique_seed)}'
var vaultName = '${vaultBase}-${uniqueString(unique_seed)}'
// var componentsFunctionAppName = '${componentsFunctionAppBase}-${uniqueString(unique_seed)}'
var searchServicesName = '${searchServicesBase}-${uniqueString(unique_seed)}'
var storageAccountName = toLower('${storageAccountBase}${uniqueString(unique_seed)}') // Storage accounts must be lowercase and alphanumeric only



resource storageAccount 'Microsoft.Storage/storageAccounts@2022-05-01' = {
  name: storageAccountNameFunction
  location: location
  sku: {
    name: storageAccountType
  }
  kind: 'Storage'
  properties: {
    supportsHttpsTrafficOnly: true
    defaultToOAuthAuthentication: true
  }
}

resource hostingPlan 'Microsoft.Web/serverfarms@2021-03-01' = {
  name: hostingPlanName
  location: location
  sku: {
    name: 'Y1'
    tier: 'Dynamic'
  }
  properties: {}
}

resource functionApp 'Microsoft.Web/sites@2021-03-01' = {
  name: functionAppName
  location: location
  kind: 'functionapp'
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: hostingPlan.id
    siteConfig: {
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: 'DefaultEndpointsProtocol=https;AccountName=${storageAccountName};EndpointSuffix=${environment().suffixes.storage};AccountKey=${storageAccount.listKeys().keys[0].value}'
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(functionAppName)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'WEBSITE_NODE_DEFAULT_VERSION'
          value: '~14'
        }
        {
          name: 'APPINSIGHTS_INSTRUMENTATIONKEY'
          value: applicationInsights.properties.InstrumentationKey
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: functionWorkerRuntime
        }
      ]
      ftpsState: 'FtpsOnly'
      minTlsVersion: '1.2'
    }
    httpsOnly: true
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

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2020-08-01' = {
  name: workspaceName
  location: location
  properties: {
    sku: {
      name: 'PerGB2018' // This is the typical SKU used; adjust as needed (e.g., Free, Standard, Premium, PerNode, PerGB2018)
    }
    retentionInDays: 30 // Set retention as needed, 0 if you want unlimited
    features: {
      searchVersion: 1
      legacy: 0
      enableLogAccessUsingOnlyResourcePermissions: true
    }
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// resource component_function_app_resource 'microsoft.insights/components@2020-02-02' = {
//   name: componentsFunctionAppName
//   location: location
//   kind: 'web'
//   properties: {
//     Application_Type: 'web'
//     Flow_Type: 'Redfield'
//     Request_Source: 'IbizaWebAppExtensionCreate'
//     RetentionInDays: 90
//     // WorkspaceResourceId: workspaces_DefaultWorkspace_253f778b_553f_4871_b143_123f314c45c1_CCAN_externalid
//     // IngestionMode: 'LogAnalytics'
//     publicNetworkAccessForIngestion: 'Enabled'
//     publicNetworkAccessForQuery: 'Enabled'
//   }
// }

resource vault_resource 'Microsoft.KeyVault/vaults@2024-04-01-preview' = {
  name: vaultName
  location: 'eastus'
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId
    networkAcls: {
      bypass: 'None'
      defaultAction: 'Allow'
      ipRules: []
      virtualNetworkRules: []
    }
    accessPolicies: []
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    enableSoftDelete: true
    softDeleteRetentionInDays: 90
    enableRbacAuthorization: true
    vaultUri: 'https://${vaultName}.vault.azure.net/'
    provisioningState: 'Succeeded'
    publicNetworkAccess: 'Enabled'
  }
}

resource searchServices_resource 'Microsoft.Search/searchServices@2024-06-01-preview' = {
  name: searchServicesName
  location: 'Central US'
  sku: {
    name: 'basic'
  }
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    replicaCount: 1
    partitionCount: 1
    hostingMode: 'default'
    publicNetworkAccess: 'Enabled'
    networkRuleSet: {
      ipRules: []
      bypass: 'None'
    }
    encryptionWithCmk: {
      enforcement: 'Unspecified'
    }
    disableLocalAuth: false
    authOptions: {
      apiKeyOnly: {}
    }
    disabledDataExfiltrationOptions: []
    semanticSearch: 'free'
  }
}

resource storage_account_resource 'Microsoft.Storage/storageAccounts@2023-05-01' = {
  name: storageAccountName
  location: location
  sku: {
    name: 'Standard_LRS'
    tier: 'Standard'
  }
  kind: 'Storage'
  properties: {
    defaultToOAuthAuthentication: true
    allowCrossTenantReplication: false
    isLocalUserEnabled: false
    minimumTlsVersion: 'TLS1_2'
    allowBlobPublicAccess: false
    allowSharedKeyAccess: false
    networkAcls: {
      resourceAccessRules: [
        {
          tenantId: tenantId
          resourceId: '/subscriptions/253f778b-553f-4871-b143-123f314c45c1/providers/Microsoft.Security/datascanners/storageDataScanner'
        }
      ]
      bypass: 'AzureServices'
      virtualNetworkRules: []
      ipRules: []
      defaultAction: 'Allow'
    }
    supportsHttpsTrafficOnly: true
    encryption: {
      services: {
        file: {
          keyType: 'Account'
          enabled: true
        }
        blob: {
          keyType: 'Account'
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }
}

// resource sites_functionapp_resource 'Microsoft.Web/sites@2023-12-01' = {
//   name: functionAppName
//   location: location
//   // tags: {
//   //   'hidden-link: /app-insights-resource-id': '/subscriptions/253f778b-553f-4871-b143-123f314c45c1/resourceGroups/functionapp912/providers/microsoft.insights/components/functionapp1025'
//   //   'hidden-link: /app-insights-instrumentation-key': '14b76a58-7595-4a88-a353-b25d7086d52e'
//   //   'hidden-link: /app-insights-conn-string': 'InstrumentationKey=14b76a58-7595-4a88-a353-b25d7086d52e;IngestionEndpoint=https://canadacentral-1.in.applicationinsights.azure.com/;LiveEndpoint=https://canadacentral.livediagnostics.monitor.azure.com/;ApplicationId=7ac2543f-0ceb-4b11-9418-be35818620a9'
//   // }
//   kind: 'functionapp,linux'
//   identity: {
//     type: 'SystemAssigned'
//   }
//   properties: {
//     enabled: true
//     hostNameSslStates: [
//       {
//         name: '${functionAppName}.azurewebsites.net'
//         sslState: 'Disabled'
//         hostType: 'Standard'
//       }
//       {
//         name: '${functionAppName}.scm.azurewebsites.net'
//         sslState: 'Disabled'
//         hostType: 'Repository'
//       }
//     ]
//     serverFarmId: newServerFarm.id
//     reserved: true
//     isXenon: false
//     hyperV: false
//     dnsConfiguration: {}
//     vnetRouteAllEnabled: false
//     vnetImagePullEnabled: false
//     vnetContentShareEnabled: false
//     siteConfig: {
//       numberOfWorkers: 1
//       linuxFxVersion: 'Python|3.11'
//       acrUseManagedIdentityCreds: false
//       alwaysOn: false
//       http20Enabled: false
//       functionAppScaleLimit: 200
//       minimumElasticInstanceCount: 0,

//     }
//     scmSiteAlsoStopped: false
//     clientAffinityEnabled: false
//     clientCertEnabled: false
//     clientCertMode: 'Required'
//     hostNamesDisabled: false
//     vnetBackupRestoreEnabled: false
//     customDomainVerificationId: '799804A9311D5BE0A804FB20F417C8445751EEE55C6662A510C1720C57B460AF'
//     containerSize: 1536
//     dailyMemoryTimeQuota: 0
//     httpsOnly: true
//     redundancyMode: 'None'
//     publicNetworkAccess: 'Enabled'
//     storageAccountRequired: false
//     keyVaultReferenceIdentity: 'SystemAssigned'
//   }
// }

// resource components_degradationindependencyduration 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
//   parent: component_function_app_resource
//   name: 'degradationindependencyduration'
//   location: location
//   properties: {
//     RuleDefinitions: {
//       Name: 'degradationindependencyduration'
//       DisplayName: 'Degradation in dependency duration'
//       Description: 'Smart Detection rules notify you of performance anomaly issues.'
//       HelpUrl: 'https://docs.microsoft.com/en-us/azure/application-insights/app-insights-proactive-performance-diagnostics'
//       IsHidden: false
//       IsEnabledByDefault: true
//       IsInPreview: false
//       SupportsEmailNotifications: true
//     }
//     Enabled: true
//     SendEmailsToSubscriptionOwners: true
//     CustomEmails: []
//   }
// }

// resource components_degradationinserverresponsetime 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
//   parent: component_function_app_resource
//   name: 'degradationinserverresponsetime'
//   location: location
//   properties: {
//     RuleDefinitions: {
//       Name: 'degradationinserverresponsetime'
//       DisplayName: 'Degradation in server response time'
//       Description: 'Smart Detection rules notify you of performance anomaly issues.'
//       HelpUrl: 'https://docs.microsoft.com/en-us/azure/application-insights/app-insights-proactive-performance-diagnostics'
//       IsHidden: false
//       IsEnabledByDefault: true
//       IsInPreview: false
//       SupportsEmailNotifications: true
//     }
//     Enabled: true
//     SendEmailsToSubscriptionOwners: true
//     CustomEmails: []
//   }
// }

// resource components_digestMailConfiguration 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
//   parent: component_function_app_resource
//   name: 'digestMailConfiguration'
//   location: location
//   properties: {
//     RuleDefinitions: {
//       Name: 'digestMailConfiguration'
//       DisplayName: 'Digest Mail Configuration'
//       Description: 'This rule describes the digest mail preferences'
//       HelpUrl: 'www.homail.com'
//       IsHidden: true
//       IsEnabledByDefault: true
//       IsInPreview: false
//       SupportsEmailNotifications: true
//     }
//     Enabled: true
//     SendEmailsToSubscriptionOwners: true
//     CustomEmails: []
//   }
// }

// resource components_extension_billingdatavolumedailyspikeextension 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
//   parent: component_function_app_resource
//   name: 'extension_billingdatavolumedailyspikeextension'
//   location: location
//   properties: {
//     RuleDefinitions: {
//       Name: 'extension_billingdatavolumedailyspikeextension'
//       DisplayName: 'Abnormal rise in daily data volume (preview)'
//       Description: 'This detection rule automatically analyzes the billing data generated by your application, and can warn you about an unusual increase in your application\'s billing costs'
//       HelpUrl: 'https://github.com/Microsoft/ApplicationInsights-Home/tree/master/SmartDetection/billing-data-volume-daily-spike.md'
//       IsHidden: false
//       IsEnabledByDefault: true
//       IsInPreview: true
//       SupportsEmailNotifications: false
//     }
//     Enabled: true
//     SendEmailsToSubscriptionOwners: true
//     CustomEmails: []
//   }
// }

// resource components_extension_canaryextension 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
//   parent: component_function_app_resource
//   name: 'extension_canaryextension'
//   location: location
//   properties: {
//     RuleDefinitions: {
//       Name: 'extension_canaryextension'
//       DisplayName: 'Canary extension'
//       Description: 'Canary extension'
//       HelpUrl: 'https://github.com/Microsoft/ApplicationInsights-Home/blob/master/SmartDetection/'
//       IsHidden: true
//       IsEnabledByDefault: true
//       IsInPreview: true
//       SupportsEmailNotifications: false
//     }
//     Enabled: true
//     SendEmailsToSubscriptionOwners: true
//     CustomEmails: []
//   }
// }

// resource components_extension_exceptionchangeextension 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
//   parent: component_function_app_resource
//   name: 'extension_exceptionchangeextension'
//   location: location
//   properties: {
//     RuleDefinitions: {
//       Name: 'extension_exceptionchangeextension'
//       DisplayName: 'Abnormal rise in exception volume (preview)'
//       Description: 'This detection rule automatically analyzes the exceptions thrown in your application, and can warn you about unusual patterns in your exception telemetry.'
//       HelpUrl: 'https://github.com/Microsoft/ApplicationInsights-Home/blob/master/SmartDetection/abnormal-rise-in-exception-volume.md'
//       IsHidden: false
//       IsEnabledByDefault: true
//       IsInPreview: true
//       SupportsEmailNotifications: false
//     }
//     Enabled: true
//     SendEmailsToSubscriptionOwners: true
//     CustomEmails: []
//   }
// }

// resource components_extension_memoryleakextension 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
//   parent: component_function_app_resource
//   name: 'extension_memoryleakextension'
//   location: location
//   properties: {
//     RuleDefinitions: {
//       Name: 'extension_memoryleakextension'
//       DisplayName: 'Potential memory leak detected (preview)'
//       Description: 'This detection rule automatically analyzes the memory consumption of each process in your application, and can warn you about potential memory leaks or increased memory consumption.'
//       HelpUrl: 'https://github.com/Microsoft/ApplicationInsights-Home/tree/master/SmartDetection/memory-leak.md'
//       IsHidden: false
//       IsEnabledByDefault: true
//       IsInPreview: true
//       SupportsEmailNotifications: false
//     }
//     Enabled: true
//     SendEmailsToSubscriptionOwners: true
//     CustomEmails: []
//   }
// }

// resource components_extension_securityextensionspackage 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
//   parent: component_function_app_resource
//   name: 'extension_securityextensionspackage'
//   location: location
//   properties: {
//     RuleDefinitions: {
//       Name: 'extension_securityextensionspackage'
//       DisplayName: 'Potential security issue detected (preview)'
//       Description: 'This detection rule automatically analyzes the telemetry generated by your application and detects potential security issues.'
//       HelpUrl: 'https://github.com/Microsoft/ApplicationInsights-Home/blob/master/SmartDetection/application-security-detection-pack.md'
//       IsHidden: false
//       IsEnabledByDefault: true
//       IsInPreview: true
//       SupportsEmailNotifications: false
//     }
//     Enabled: true
//     SendEmailsToSubscriptionOwners: true
//     CustomEmails: []
//   }
// }

// resource components_extension_traceseveritydetector 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
//   parent: component_function_app_resource
//   name: 'extension_traceseveritydetector'
//   location: location
//   properties: {
//     RuleDefinitions: {
//       Name: 'extension_traceseveritydetector'
//       DisplayName: 'Degradation in trace severity ratio (preview)'
//       Description: 'This detection rule automatically analyzes the trace logs emitted from your application, and can warn you about unusual patterns in the severity of your trace telemetry.'
//       HelpUrl: 'https://github.com/Microsoft/ApplicationInsights-Home/blob/master/SmartDetection/degradation-in-trace-severity-ratio.md'
//       IsHidden: false
//       IsEnabledByDefault: true
//       IsInPreview: true
//       SupportsEmailNotifications: false
//     }
//     Enabled: true
//     SendEmailsToSubscriptionOwners: true
//     CustomEmails: []
//   }
// }

// resource components_longdependencyduration 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
//   parent: component_function_app_resource
//   name: 'longdependencyduration'
//   location: location
//   properties: {
//     RuleDefinitions: {
//       Name: 'longdependencyduration'
//       DisplayName: 'Long dependency duration'
//       Description: 'Smart Detection rules notify you of performance anomaly issues.'
//       HelpUrl: 'https://docs.microsoft.com/en-us/azure/application-insights/app-insights-proactive-performance-diagnostics'
//       IsHidden: false
//       IsEnabledByDefault: true
//       IsInPreview: false
//       SupportsEmailNotifications: true
//     }
//     Enabled: true
//     SendEmailsToSubscriptionOwners: true
//     CustomEmails: []
//   }
// }

// resource components_migrationToAlertRulesCompleted 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
//   parent: component_function_app_resource
//   name: 'migrationToAlertRulesCompleted'
//   location: location
//   properties: {
//     RuleDefinitions: {
//       Name: 'migrationToAlertRulesCompleted'
//       DisplayName: 'Migration To Alert Rules Completed'
//       Description: 'A configuration that controls the migration state of Smart Detection to Smart Alerts'
//       HelpUrl: 'https://docs.microsoft.com/en-us/azure/application-insights/app-insights-proactive-performance-diagnostics'
//       IsHidden: true
//       IsEnabledByDefault: false
//       IsInPreview: true
//       SupportsEmailNotifications: false
//     }
//     Enabled: false
//     SendEmailsToSubscriptionOwners: true
//     CustomEmails: []
//   }
// }

// resource components_slowpageloadtime 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
//   parent: component_function_app_resource
//   name: 'slowpageloadtime'
//   location: location
//   properties: {
//     RuleDefinitions: {
//       Name: 'slowpageloadtime'
//       DisplayName: 'Slow page load time'
//       Description: 'Smart Detection rules notify you of performance anomaly issues.'
//       HelpUrl: 'https://docs.microsoft.com/en-us/azure/application-insights/app-insights-proactive-performance-diagnostics'
//       IsHidden: false
//       IsEnabledByDefault: true
//       IsInPreview: false
//       SupportsEmailNotifications: true
//     }
//     Enabled: true
//     SendEmailsToSubscriptionOwners: true
//     CustomEmails: []
//   }
// }

// resource components_slowserverresponsetime 'microsoft.insights/components/ProactiveDetectionConfigs@2018-05-01-preview' = {
//   parent: component_function_app_resource
//   name: 'slowserverresponsetime'
//   location: location
//   properties: {
//     RuleDefinitions: {
//       Name: 'slowserverresponsetime'
//       DisplayName: 'Slow server response time'
//       Description: 'Smart Detection rules notify you of performance anomaly issues.'
//       HelpUrl: 'https://docs.microsoft.com/en-us/azure/application-insights/app-insights-proactive-performance-diagnostics'
//       IsHidden: false
//       IsEnabledByDefault: true
//       IsInPreview: false
//       SupportsEmailNotifications: true
//     }
//     Enabled: true
//     SendEmailsToSubscriptionOwners: true
//     CustomEmails: []
//   }
// }

// resource vaults_functionapp1016_name_aoai_key 'Microsoft.KeyVault/vaults/keys@2024-04-01-preview' = {
//   parent: vault_resource
//   name: 'aoai-key'
//   location: 'eastus'
//   properties: {
//     attributes: {
//       enabled: true
//       exportable: false
//     }
//   }
// }

// resource vaults_functionapp1016_name_remmey_aoai 'Microsoft.KeyVault/vaults/secrets@2024-04-01-preview' = {
//   parent: vault_resource
//   name: 'remmey-aoai'
//   location: 'eastus'
//   properties: {
//     attributes: {
//       enabled: true
//     }
//   }
// }

resource storage_account_default_resource 'Microsoft.Storage/storageAccounts/blobServices@2023-05-01' = {
  parent: storage_account_resource
  name: 'default'
  sku: {
    name: 'Standard_LRS'
    tier: 'Standard'
  }
  properties: {
    cors: {
      corsRules: []
    }
    deleteRetentionPolicy: {
      allowPermanentDelete: false
      enabled: false
    }
  }
}

resource storageAccountsFileServiceDefault 'Microsoft.Storage/storageAccounts/fileServices@2023-05-01' = {
  parent: storage_account_resource
  name: 'default'
  sku: {
    name: 'Standard_LRS'
    tier: 'Standard'
  }
  properties: {
    protocolSettings: {
      smb: {}
    }
    cors: {
      corsRules: []
    }
    shareDeleteRetentionPolicy: {
      enabled: true
      days: 7
    }
  }
}

resource storageAccountQueueServiceDefault 'Microsoft.Storage/storageAccounts/queueServices@2023-05-01' = {
  parent: storage_account_resource
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
  }
}

resource storageAccountTableServiceDefault 'Microsoft.Storage/storageAccounts/tableServices@2023-05-01' = {
  parent: storage_account_resource
  name: 'default'
  properties: {
    cors: {
      corsRules: []
    }
  }
}

// resource function_app_ftp_credentials 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2023-12-01' = {
//   parent: sites_functionapp_resource
//   name: 'ftp'
//   location: location
//   // tags: {
//   //   'hidden-link: /app-insights-resource-id': '/subscriptions/253f778b-553f-4871-b143-123f314c45c1/resourceGroups/functionapp912/providers/microsoft.insights/components/functionapp1025'
//   //   'hidden-link: /app-insights-instrumentation-key': '14b76a58-7595-4a88-a353-b25d7086d52e'
//   //   'hidden-link: /app-insights-conn-string': 'InstrumentationKey=14b76a58-7595-4a88-a353-b25d7086d52e;IngestionEndpoint=https://canadacentral-1.in.applicationinsights.azure.com/;LiveEndpoint=https://canadacentral.livediagnostics.monitor.azure.com/;ApplicationId=7ac2543f-0ceb-4b11-9418-be35818620a9'
//   // }
//   properties: {
//     allow: false
//   }
// }

// resource sites_name_scm 'Microsoft.Web/sites/basicPublishingCredentialsPolicies@2023-12-01' = {
//   parent: sites_functionapp_resource
//   name: 'scm'
//   location: location
//   // tags: {
//   //   'hidden-link: /app-insights-resource-id': '/subscriptions/253f778b-553f-4871-b143-123f314c45c1/resourceGroups/functionapp912/providers/microsoft.insights/components/functionapp1025'
//   //   'hidden-link: /app-insights-instrumentation-key': '14b76a58-7595-4a88-a353-b25d7086d52e'
//   //   'hidden-link: /app-insights-conn-string': 'InstrumentationKey=14b76a58-7595-4a88-a353-b25d7086d52e;IngestionEndpoint=https://canadacentral-1.in.applicationinsights.azure.com/;LiveEndpoint=https://canadacentral.livediagnostics.monitor.azure.com/;ApplicationId=7ac2543f-0ceb-4b11-9418-be35818620a9'
//   // }
//   properties: {
//     allow: false
//   }
// }

// resource sites_name_web 'Microsoft.Web/sites/config@2023-12-01' = {
//   parent: sites_functionapp_resource
//   name: 'web'
//   location: location
//   // tags: {
//   //   'hidden-link: /app-insights-resource-id': '/subscriptions/253f778b-553f-4871-b143-123f314c45c1/resourceGroups/functionapp912/providers/microsoft.insights/components/functionapp1025'
//   //   'hidden-link: /app-insights-instrumentation-key': '14b76a58-7595-4a88-a353-b25d7086d52e'
//   //   'hidden-link: /app-insights-conn-string': 'InstrumentationKey=14b76a58-7595-4a88-a353-b25d7086d52e;IngestionEndpoint=https://canadacentral-1.in.applicationinsights.azure.com/;LiveEndpoint=https://canadacentral.livediagnostics.monitor.azure.com/;ApplicationId=7ac2543f-0ceb-4b11-9418-be35818620a9'
//   // }
//   properties: {
//     numberOfWorkers: 1
//     defaultDocuments: [
//       'Default.htm'
//       'Default.html'
//       'Default.asp'
//       'index.htm'
//       'index.html'
//       'iisstart.htm'
//       'default.aspx'
//       'index.php'
//     ]
//     netFrameworkVersion: 'v4.0'
//     linuxFxVersion: 'Python|3.11'
//     requestTracingEnabled: false
//     remoteDebuggingEnabled: false
//     httpLoggingEnabled: false
//     acrUseManagedIdentityCreds: false
//     logsDirectorySizeLimit: 35
//     detailedErrorLoggingEnabled: false
//     publishingUsername: 'REDACTED'
//     scmType: 'None'
//     use32BitWorkerProcess: false
//     webSocketsEnabled: false
//     alwaysOn: false
//     managedPipelineMode: 'Integrated'
//     virtualApplications: [
//       {
//         virtualPath: '/'
//         physicalPath: 'site\\wwwroot'
//         preloadEnabled: false
//       }
//     ]
//     loadBalancing: 'LeastRequests'
//     experiments: {
//       rampUpRules: []
//     }
//     autoHealEnabled: false
//     vnetRouteAllEnabled: false
//     vnetPrivatePortsCount: 0
//     publicNetworkAccess: 'Enabled'
//     cors: {
//       allowedOrigins: [
//         'https://ms.portal.azure.com'
//       ]
//       supportCredentials: false
//     }
//     localMySqlEnabled: false
//     managedServiceIdentityId: 28988
//     ipSecurityRestrictions: [
//       {
//         ipAddress: 'Any'
//         action: 'Allow'
//         priority: 2147483647
//         name: 'Allow all'
//         description: 'Allow all access'
//       }
//     ]
//     scmIpSecurityRestrictions: [
//       {
//         ipAddress: 'Any'
//         action: 'Allow'
//         priority: 2147483647
//         name: 'Allow all'
//         description: 'Allow all access'
//       }
//     ]
//     scmIpSecurityRestrictionsUseMain: false
//     http20Enabled: false
//     minTlsVersion: '1.2'
//     scmMinTlsVersion: '1.2'
//     ftpsState: 'FtpsOnly'
//     preWarmedInstanceCount: 0
//     functionAppScaleLimit: 200
//     functionsRuntimeScaleMonitoringEnabled: false
//     minimumElasticInstanceCount: 0
//     azureStorageAccounts: {}
//   }
// }

// resource sites_functionapp1025_name_call_aoai 'Microsoft.Web/sites/functions@2023-12-01' = {
//   parent: sites_functionapp_resource
//   name: 'call_aoai'
//   location: location
//   properties: {
//     script_root_path_href: 'https://functionapp1025.azurewebsites.net/admin/vfs/home/site/wwwroot/call_aoai/'
//     script_href: 'https://functionapp1025.azurewebsites.net/admin/vfs/home/site/wwwroot/call_aoai/__init__.py'
//     config_href: 'https://functionapp1025.azurewebsites.net/admin/vfs/home/site/wwwroot/call_aoai/function.json'
//     test_data_href: 'https://functionapp1025.azurewebsites.net/admin/vfs/tmp/FunctionsData/call_aoai.dat'
//     href: 'https://functionapp1025.azurewebsites.net/admin/functions/call_aoai'
//     config: {
//       bindings: [
//         {
//           name: 'myblob'
//           type: 'blobTrigger'
//           direction: 'in'
//           path: 'silver/{name}'
//           connection: 'AzureWebJobsStorage'
//         }
//       ]
//     }
//     language: 'python'
//     isDisabled: false
//   }
// }

// resource sites_functionapp1025_name_call_text_analytics 'Microsoft.Web/sites/functions@2023-12-01' = {
//   parent: sites_functionapp_resource
//   name: 'call_text_analytics'
//   location: location
//   properties: {
//     script_root_path_href: 'https://functionapp1025.azurewebsites.net/admin/vfs/home/site/wwwroot/call_text_analytics/'
//     script_href: 'https://functionapp1025.azurewebsites.net/admin/vfs/home/site/wwwroot/call_text_analytics/__init__.py'
//     config_href: 'https://functionapp1025.azurewebsites.net/admin/vfs/home/site/wwwroot/call_text_analytics/function.json'
//     test_data_href: 'https://functionapp1025.azurewebsites.net/admin/vfs/tmp/FunctionsData/call_text_analytics.dat'
//     href: 'https://functionapp1025.azurewebsites.net/admin/functions/call_text_analytics'
//     config: {
//       bindings: [
//         {
//           authLevel: 'function'
//           type: 'httpTrigger'
//           direction: 'in'
//           name: 'req'
//           methods: [
//             'get'
//             'post'
//           ]
//         }
//         {
//           type: 'http'
//           direction: 'out'
//           name: '$return'
//         }
//       ]
//     }
//     invoke_url_template: 'https://functionapp1025.azurewebsites.net/api/call_text_analytics'
//     language: 'python'
//     isDisabled: false
//   }
// }

// resource sites_functionapp1025_name_process_uploads 'Microsoft.Web/sites/functions@2023-12-01' = {
//   parent: sites_functionapp_resource
//   name: 'process_uploads'
//   location: location
//   properties: {
//     script_root_path_href: 'https://functionapp1025.azurewebsites.net/admin/vfs/home/site/wwwroot/process_uploads/'
//     script_href: 'https://functionapp1025.azurewebsites.net/admin/vfs/home/site/wwwroot/process_uploads/__init__.py'
//     config_href: 'https://functionapp1025.azurewebsites.net/admin/vfs/home/site/wwwroot/process_uploads/function.json'
//     test_data_href: 'https://functionapp1025.azurewebsites.net/admin/vfs/tmp/FunctionsData/process_uploads.dat'
//     href: 'https://functionapp1025.azurewebsites.net/admin/functions/process_uploads'
//     config: {
//       bindings: [
//         {
//           authLevel: 'function'
//           type: 'httpTrigger'
//           direction: 'in'
//           name: 'req'
//           methods: [
//             'get'
//             'post'
//           ]
//         }
//       ]
//     }
//     invoke_url_template: 'https://functionapp1025.azurewebsites.net/api/process_uploads'
//     language: 'python'
//     isDisabled: false
//   }
// }

// resource sites_functionapp1025_name_transcribe 'Microsoft.Web/sites/functions@2023-12-01' = {
//   parent: sites_functionapp_resource
//   name: 'transcribe'
//   location: location
//   properties: {
//     script_root_path_href: 'https://functionapp1025.azurewebsites.net/admin/vfs/home/site/wwwroot/transcribe/'
//     script_href: 'https://functionapp1025.azurewebsites.net/admin/vfs/home/site/wwwroot/transcribe/__init__.py'
//     config_href: 'https://functionapp1025.azurewebsites.net/admin/vfs/home/site/wwwroot/transcribe/function.json'
//     test_data_href: 'https://functionapp1025.azurewebsites.net/admin/vfs/tmp/FunctionsData/transcribe.dat'
//     href: 'https://functionapp1025.azurewebsites.net/admin/functions/transcribe'
//     config: {
//       bindings: [
//         {
//           authLevel: 'function'
//           type: 'httpTrigger'
//           direction: 'in'
//           name: 'req'
//           methods: [
//             'get'
//             'post'
//           ]
//         }
//         {
//           type: 'http'
//           direction: 'out'
//           name: '$return'
//         }
//       ]
//     }
//     invoke_url_template: 'https://functionapp1025.azurewebsites.net/api/transcribe'
//     language: 'python'
//     isDisabled: false
//   }
// }

// resource sites_functionapp1025_name_whisper 'Microsoft.Web/sites/functions@2023-12-01' = {
//   parent: sites_functionapp_resource
//   name: 'whisper'
//   location: location
//   properties: {
//     script_root_path_href: 'https://functionapp1025.azurewebsites.net/admin/vfs/home/site/wwwroot/whisper/'
//     script_href: 'https://functionapp1025.azurewebsites.net/admin/vfs/home/site/wwwroot/whisper/__init__.py'
//     config_href: 'https://functionapp1025.azurewebsites.net/admin/vfs/home/site/wwwroot/whisper/function.json'
//     test_data_href: 'https://functionapp1025.azurewebsites.net/admin/vfs/tmp/FunctionsData/whisper.dat'
//     href: 'https://functionapp1025.azurewebsites.net/admin/functions/whisper'
//     config: {
//       bindings: [
//         {
//           authLevel: 'function'
//           type: 'httpTrigger'
//           direction: 'in'
//           name: 'req'
//           methods: [
//             'get'
//             'post'
//           ]
//         }
//       ]
//     }
//     invoke_url_template: 'https://functionapp1025.azurewebsites.net/api/whisper'
//     language: 'python'
//     isDisabled: false
//   }
// }

// resource sites_name_sites_functionapp1025_name_azurewebsites_net 'Microsoft.Web/sites/hostNameBindings@2023-12-01' = {
//   parent: sites_functionapp_resource
//   name: '${functionAppName}.azurewebsites.net'
//   location: location
//   properties: {
//     siteName: 'functionapp1025'
//     hostNameType: 'Verified'
//   }
// }

// resource storageAccountBlobContainerDefault 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
//   parent: storage_account_default_resource
//   name: 'azure-webjobs-hosts'
//   properties: {
//     immutableStorageWithVersioning: {
//       enabled: false
//     }
//     defaultEncryptionScope: '$account-encryption-key'
//     denyEncryptionScopeOverride: false
//     publicAccess: 'None'
//   }
//   // dependsOn: [
//   //   storage_account_resource
//   // ]
// }

// resource functionAppStorageAccountContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
//   parent: storage_account_default_resource
//   name: 'azure-webjobs-secrets'
//   properties: {
//     immutableStorageWithVersioning: {
//       enabled: false
//     }
//     defaultEncryptionScope: '$account-encryption-key'
//     denyEncryptionScopeOverride: false
//     publicAccess: 'None'
//   }
//   // dependsOn: [
//   //   storage_account_resource
//   // ]
// }

resource storageAccountFunctionAppBlobContainer 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: storage_account_default_resource
  name: 'bronze'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
}

resource defaultBlobContainer_gold 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: storage_account_default_resource
  name: 'gold'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
  // dependsOn: [
  //   storage_account_resource
  // ]
}

resource storageAccounts_reference 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: storage_account_default_resource
  name: 'reference'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
  // dependsOn: [
  //   storage_account_resource
  // ]
}

// resource storageAccounts_functionapp912b6f8_name_default_scm_releases 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
//   parent: storage_account_default_resource
//   name: 'scm-releases'
//   properties: {
//     immutableStorageWithVersioning: {
//       enabled: false
//     }
//     defaultEncryptionScope: '$account-encryption-key'
//     denyEncryptionScopeOverride: false
//     publicAccess: 'None'
//   }
//   // dependsOn: [
//   //   storage_account_resource
//   // ]
// }

resource storageAccounts_functionapp912b6f8_name_default_silver 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: storage_account_default_resource
  name: 'silver'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
  // dependsOn: [
  //   storage_account_resource
  // ]
}

resource storageAccounts_functionapp912b6f8_name_default_ui_uploads 'Microsoft.Storage/storageAccounts/blobServices/containers@2023-05-01' = {
  parent: storage_account_default_resource
  name: 'ui-uploads'
  properties: {
    immutableStorageWithVersioning: {
      enabled: false
    }
    defaultEncryptionScope: '$account-encryption-key'
    denyEncryptionScopeOverride: false
    publicAccess: 'None'
  }
  // dependsOn: [
  //   storage_account_resource
  // ]
}

// resource storageAccounts_functionapp912b6f8_name_default_azure_webjobs_blobtrigger_functionapp1025 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-05-01' = {
//   parent: storageAccountQueueServiceDefault
//   name: 'azure-webjobs-blobtrigger-functionapp1025'
//   properties: {
//     metadata: {}
//   }
//   // dependsOn: [
//   //   storage_account_resource
//   // ]
// }

// resource storageAccounts_functionapp912b6f8_name_default_webjobs_blobtrigger_poison 'Microsoft.Storage/storageAccounts/queueServices/queues@2023-05-01' = {
//   parent: storageAccountQueueServiceDefault
//   name: 'webjobs-blobtrigger-poison'
//   properties: {
//     metadata: {}
//   }
//   // dependsOn: [
//   //   storage_account_resource
//   // ]
// }

// resource storageAccounts_functionapp912b6f8_name_default_AzureFunctionsDiagnosticEvents202411 'Microsoft.Storage/storageAccounts/tableServices/tables@2023-05-01' = {
//   parent: storageAccountTableServiceDefault
//   name: 'AzureFunctionsDiagnosticEvents202411'
//   properties: {}
//   // dependsOn: [
//   //   storage_account_resource
//   // ]
// }
