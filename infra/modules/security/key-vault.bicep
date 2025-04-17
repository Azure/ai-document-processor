import { roleAssignmentInfo } from '../security/managed-identity.bicep'
import { diagnosticSettingsInfo } from '../management_governance/log-analytics-workspace.bicep'

@description('Name of the resource.')
param name string
@description('Location to deploy the resource. Defaults to the location of the resource group.')
param location string = resourceGroup().location
@description('Tags for the resource.')
param tags object = {}

param keyVaultReuse bool
param existingKeyVaultResourceGroupName string

param publicNetworkAccess string = 'Enabled'

@description('Secret Keys to add to App Configuration')
param secureAppSettings array = []

param subnets array = []

@description('Key Vault SKU name. Defaults to standard.')
@allowed([
  'standard'
  'premium'
])
param skuName string = 'standard'
@description('Whether soft deletion is enabled. Defaults to true.')
param enableSoftDelete bool = true
@description('Number of days to retain soft-deleted keys, secrets, and certificates. Defaults to 90.')
param retentionInDays int = 90
@description('Whether purge protection is enabled. Defaults to true.')
param enablePurgeProtection bool = true
@description('Role assignments to create for the Key Vault.')
param roleAssignments roleAssignmentInfo[] = []
@description('Name of the Log Analytics Workspace to use for diagnostic settings.')
param logAnalyticsWorkspaceName string?
@description('Diagnostic settings to configure for the Key Vault instance. Defaults to all logs and metrics.')
param diagnosticSettings diagnosticSettingsInfo = {
  logs: [
    {
      categoryGroup: 'allLogs'
      enabled: true
    }
  ]
  metrics: [
    {
      category: 'AllMetrics'
      enabled: true
    }
  ]
}

resource existingKeyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' existing = if (keyVaultReuse) {
  scope: resourceGroup(existingKeyVaultResourceGroupName)
  name: name
}

resource keyVault 'Microsoft.KeyVault/vaults@2024-04-01-preview' = if (!keyVaultReuse) {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: skuName
    }
    tenantId: subscription().tenantId
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
      ipRules: []
      virtualNetworkRules: [
        
      ]
    }
    accessPolicies: []
    enableSoftDelete: enableSoftDelete
    enabledForTemplateDeployment: true
    enableRbacAuthorization: true
    enablePurgeProtection: enablePurgeProtection
    softDeleteRetentionInDays: retentionInDays
    publicNetworkAccess: publicNetworkAccess
  }
}

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for roleAssignment in roleAssignments: {
    name: guid(keyVault.id, roleAssignment.principalId, roleAssignment.roleDefinitionId)
    scope: keyVault
    properties: {
      principalId: roleAssignment.principalId
      roleDefinitionId: roleAssignment.roleDefinitionId
      principalType: roleAssignment.principalType
    }
  }
]

resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' existing = if (logAnalyticsWorkspaceName != null) {
  name: logAnalyticsWorkspaceName!
}

resource keyVaultDiagnosticSettings 'Microsoft.Insights/diagnosticSettings@2021-05-01-preview' = if (logAnalyticsWorkspaceName != null) {
  name: '${keyVault.name}-diagnostic-settings'
  scope: keyVault
  properties: {
    workspaceId: logAnalyticsWorkspace.id
    logs: diagnosticSettings!.logs
    metrics: diagnosticSettings!.metrics
  }
}

// Secret in Key Vault
resource secret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = [for (config, i) in secureAppSettings: {
  parent: keyVault
  name: replace(config.name, '_', '-')
  properties: {
      contentType: 'string'
      value:  config.value
  }
  tags: {}
}
]

@description('ID for the deployed Key Vault resource.')
output id string = keyVaultReuse ? existingKeyVault.id: keyVault.id
@description('Name for the deployed Key Vault resource.')
output name string = keyVaultReuse ? existingKeyVault.name: keyVault.name
@description('URI for the deployed Key Vault resource.')
output uri string = keyVaultReuse ? existingKeyVault.properties.vaultUri: keyVault.properties.vaultUri
@description('Urls to the secrets created in the Key Vault for app config')
output secrets array = [for (config, i) in secureAppSettings: {
  name: config.name
  value: concat('{"uri":"',secret[i].properties.secretUri, '"}')
}]
