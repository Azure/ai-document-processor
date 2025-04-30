// Copyright (c) Microsoft Corporation.
// Licensed under the MIT License.

param privateLinkScopeName string
param privateLinkScopedResources array = []
param queryAccessMode string = 'Open'
param ingestionAccessMode string = 'PrivateOnly'

resource privateLinkScope 'Microsoft.Insights/privateLinkScopes@2023-06-01-preview' = {
  name: privateLinkScopeName
  location: 'global'
  properties: {
    accessModeSettings: {
      queryAccessMode: queryAccessMode
      ingestionAccessMode: ingestionAccessMode
    }
  }
}

resource scopedResources 'Microsoft.Insights/privateLinkScopes/scopedResources@2023-06-01-preview' = [
  for id in privateLinkScopedResources: {
    name: uniqueString(id)
    parent: privateLinkScope
    properties: {
      kind: 'Resource'
      linkedResourceId: id
      subscriptionLocation: resourceGroup().location
    }
  }
]

output name string = privateLinkScope.name
output id string = privateLinkScope.id
