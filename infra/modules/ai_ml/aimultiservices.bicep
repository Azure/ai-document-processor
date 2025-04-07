@description('Azure AI Multi Services name. It has to be unique. Type a name followed by your resource group name. (<name>-<resourceGroupName>)')
param aiMultiServicesName string

@description('Location for all resources.')
param location string = resourceGroup().location

param identityId string
param publicNetworkAccess string = 'Enabled'

@allowed([
  'S0'
])
param sku string = 'S0'

resource aiMultiServices 'Microsoft.CognitiveServices/accounts@2024-10-01' = {
  name: aiMultiServicesName
  location: location
  sku: {
    name: sku
  }
  identity: {
    type: identityId == null ? 'SystemAssigned' : 'UserAssigned'
    userAssignedIdentities: identityId == null
      ? null
      : {
          '${identityId}': {
            //principalId: identityPrincipalId
            //clientId: identityClientId
          }
        }
  }
  kind: 'CognitiveServices'
  properties: {
    customSubDomainName: aiMultiServicesName
    publicNetworkAccess: publicNetworkAccess
    networkAcls: {
      defaultAction: 'Allow'
    }    
  }
}

output id string = aiMultiServices.id
output aiMultiServicesName string = aiMultiServices.name
output aiMultiServicesEndpoint string = aiMultiServices.properties.endpoint
