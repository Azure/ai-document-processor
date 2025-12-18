// EventGrid Blob Subscription Module
// This is deployed AFTER function code deployment (via postdeploy hook)
// because the blobs_extension key only exists after the blob trigger function initializes

@description('Name of the storage account to subscribe to')
param storageAccountName string

@description('Name of the EventGrid subscription')
param subscriptionName string = 'bronze-blob-trigger'

@description('The webhook endpoint URL including the blobs_extension key')
@secure()
param webhookEndpoint string

@description('Container path filter (e.g., /blobServices/default/containers/bronze/)')
param subjectBeginsWith string = '/blobServices/default/containers/bronze/'

@description('Event types to subscribe to')
param includedEventTypes array = ['Microsoft.Storage.BlobCreated']

// Reference existing storage account
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
  name: storageAccountName
}

// Create EventGrid subscription on the storage account
resource eventSubscription 'Microsoft.EventGrid/eventSubscriptions@2024-06-01-preview' = {
  name: subscriptionName
  scope: storageAccount
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: webhookEndpoint
      }
    }
    filter: {
      includedEventTypes: includedEventTypes
      subjectBeginsWith: subjectBeginsWith
    }
    eventDeliverySchema: 'EventGridSchema'
    retryPolicy: {
      maxDeliveryAttempts: 30
      eventTimeToLiveInMinutes: 1440
    }
  }
}

output subscriptionId string = eventSubscription.id
output subscriptionName string = eventSubscription.name
