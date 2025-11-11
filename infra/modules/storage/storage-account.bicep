import { roleAssignmentInfo } from '../security/managed-identity.bicep'

@description('Name of the resource.')
param name string
@description('Location to deploy the resource. Defaults to the location of the resource group.')
param location string = resourceGroup().location
@description('Tags for the resource.')
param tags object = {}
@description('MSI id for resource.')
param identityId string?
@description('Whether to enable public network access. Defaults to Enabled.')
@allowed([
  'Enabled'
  'Disabled'
])
param publicNetworkAccess string = 'Enabled'
param existingStorageResourceGroupName string
param storageReuse bool
param deployStorageAccount bool = true

param allowBlobPublicAccess bool = false
param allowCrossTenantReplication bool = true
param allowSharedKeyAccess bool = false
param defaultToOAuthAuthentication bool = false
param deleteRetentionPolicy object = {}
@allowed([ 'AzureDnsZone', 'Standard' ])
param dnsEndpointType string = 'Standard'
param kind string = 'StorageV2'
param minimumTlsVersion string = 'TLS1_2'
param containers array = []
param networkAcls object = {
  defaultAction: 'Allow'
  bypass: 'AzureServices'
  ipRules: []
  virtualNetworkRules: []
  resourceAccessRules: []
}

@export()
@description('SKU information for Storage Account.')
type skuInfo = {
  @description('Name of the SKU.')
  name:
    | 'Premium_LRS'
    | 'Premium_ZRS'
    | 'Standard_GRS'
    | 'Standard_GZRS'
    | 'Standard_LRS'
    | 'Standard_RAGRS'
    | 'Standard_RAGZRS'
    | 'Standard_ZRS'
}

@export()
@description('Information about the blob container retention policy for the Storage Account.')
type blobContainerRetentionInfo = {
  @description('Indicates whether permanent deletion is allowed for blob containers.')
  allowPermanentDelete: bool
  @description('Number of days to retain blobs.')
  days: int
  @description('Indicates whether the retention policy is enabled.')
  enabled: bool
}

@description('Storage Account SKU. Defaults to Standard_LRS.')
param sku skuInfo = {
  name: 'Standard_LRS'
}

@description('Access tier for the Storage Account. If the sku is a premium SKU, this will be ignored. Defaults to Hot.')
@allowed([ 'Hot', 'Cool', 'Premium' ])
param accessTier string = 'Hot'

@description('Blob container retention policy for the Storage Account. Defaults to disabled.')
param blobContainerRetention blobContainerRetentionInfo = {
  allowPermanentDelete: false
  days: 7
  enabled: false
}
@description('Whether to disable local (key-based) authentication. Defaults to true.')
param disableLocalAuth bool = false
@description('Role assignments to create for the Storage Account.')
param roleAssignments roleAssignmentInfo[] = []

resource existingStorage 'Microsoft.Storage/storageAccounts@2024-01-01' existing  = if (storageReuse && deployStorageAccount) {
  scope: resourceGroup(existingStorageResourceGroupName)
  name: name
}

resource newStorageAccount 'Microsoft.Storage/storageAccounts@2024-01-01' = {
  name: name
  location: location
  tags: tags
  kind: 'StorageV2'
  sku: sku
  identity: {
    type: identityId == null ? 'SystemAssigned' : 'UserAssigned'
    userAssignedIdentities: identityId == null
      ? null
      : {
          '${identityId}': {}
        }
  }
  properties: {
    accessTier: startsWith(sku.name, 'Premium') ? 'Premium' : accessTier
    networkAcls: networkAcls
    publicNetworkAccess: publicNetworkAccess
    allowBlobPublicAccess: allowBlobPublicAccess
    allowCrossTenantReplication: allowCrossTenantReplication
    allowSharedKeyAccess: !disableLocalAuth
    supportsHttpsTrafficOnly: true
    dnsEndpointType: dnsEndpointType
    minimumTlsVersion: minimumTlsVersion
    encryption: {
      services: {
        blob: {
          enabled: true
        }
        file: {
          enabled: true
        }
        table: {
          enabled: true
        }
        queue: {
          enabled: true
        }
      }
      keySource: 'Microsoft.Storage'
    }
  }

  resource blobServices 'blobServices@2024-01-01' = {
    name: 'default'
    properties: {
      containerDeleteRetentionPolicy: blobContainerRetention
    }
    resource container 'containers' = [for container in containers: {
      name: container.name
      properties: {
        publicAccess: contains(container, 'publicAccess') ? container.publicAccess : 'None'
      }
    }]
  }
}

resource assignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for roleAssignment in roleAssignments: {
    name: guid(newStorageAccount.id, roleAssignment.principalId, roleAssignment.roleDefinitionId)
    scope: newStorageAccount
    properties: {
      principalId: roleAssignment.principalId
      roleDefinitionId: roleAssignment.roleDefinitionId
      principalType: roleAssignment.principalType
    }
  }
]

@description('ID for the deployed Storage Account resource.')
output id string = !deployStorageAccount ? '' : storageReuse ? existingStorage.id : newStorageAccount.id
@description('Name for the deployed Storage Account resource.')
output name string = !deployStorageAccount ? '' : storageReuse ? existingStorage.name : newStorageAccount.name

output primaryEndpoints object = !deployStorageAccount ? {} : storageReuse ? existingStorage.properties.primaryEndpoints: newStorageAccount.properties.primaryEndpoints
