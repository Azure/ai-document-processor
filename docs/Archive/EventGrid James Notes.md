- Issue 0: Model version in main.bicep. Change from Sept to Aug.
- Issue 1: MI Config (Flex Consumption needs User-Assigned Identity to be explicitly called out)
  - in main.bicep add a line of code
    - ```
      module processingFunctionApp 'br/public:avm/res/web/site:0.15.1' = if (deployProcessingApp) {
        name: 'processingFunctionApp'
        params: {
          // ... other params ...
          managedIdentities: {
            systemAssigned: false
            userAssignedResourceIds: [uaiFrontendMsi.outputs.id]
          }
          keyVaultAccessIdentityResourceId: uaiFrontendMsi.outputs.id  // ← THIS WAS ADDED
          // ... rest of params ...
        }
      }
      ```
- Issue 2: Flex Consumption needs to call out EventGrid as blob trigger source
  - in function_app.py add line of code

    - ```
      @app.blob_trigger(
          arg_name="blob",
          path="bronze/{name}",
          connection="DataStorage",
          source="EventGrid",  # ← THIS WAS ADDED - Required for Flex Consumption!
      )
      ```
  - ```

    ```
- Issue 3: EventGrid Webhook subscription - to recevie eventgrid events you need the eventgrid subscription to first send the events, this is done by the eventgrid subscription
  - Can be created manually in storage account
  - Tried with postdeploy.ps1. I THINK it worked a couple times
    - Changes made to postdeploy.ps1

      ```
      # 1. Load azd environment values
      azd env get-values | ForEach-Object { ... }

      # 2. Check if subscription already exists
      $existingSubscriptions = az eventgrid event-subscription list ...
      if ($webhookSub) { exit 0 }  # Skip if exists

      # 3. Get blobs_extension key from function app
      $blobsExtensionKey = az functionapp keys list --name $functionAppName ...

      # 4. Build webhook URL
      $webhookEndpoint = "https://$functionAppName.azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.$functionName&code=$blobsExtensionKey"

      # 5. Retry loop (3 attempts)
      for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
          # Warmup requests
          for ($i = 1; $i -le 5; $i++) {
              Invoke-WebRequest -Uri $webhookEndpoint -Method POST ...
          }
          # Deploy Bicep
          az deployment group create --template-file blob-subscription.bicep ...
          if ($LASTEXITCODE -eq 0) { exit 0 }
          Start-Sleep -Seconds 30
      }

      # 6. If all retries fail, print Portal instructions and exit 0
      Write-Host "Create subscription manually in Azure Portal..."
      exit 0

      ```

      Added new bicep module: `infra/modules/eventgrid/blob-subscription.bicep`

      ```
      @description('Name of the storage account to subscribe to')
      param storageAccountName string

      @description('Name of the EventGrid subscription')
      param subscriptionName string = 'bronze-blob-trigger'

      @description('The webhook endpoint URL including the blobs_extension key')
      @secure()
      param webhookEndpoint string

      @description('Container path filter')
      param subjectBeginsWith string = '/blobServices/default/containers/bronze/'

      @description('Event types to subscribe to')
      param includedEventTypes array = ['Microsoft.Storage.BlobCreated']

      resource storageAccount 'Microsoft.Storage/storageAccounts@2023-05-01' existing = {
        name: storageAccountName
      }

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

      ```

      ```


      ```
    - change to azure.yaml
    - ```
      hooks:
        postprovision:
          # ... existing postprovision hooks ...
        postdeploy:                              # ← ADDED THIS SECTION
          posix:
            shell: sh
            run: scripts/postdeploy.sh
            interactive: true
            continueOnError: false
          windows:
            shell: pwsh
            run: scripts/postdeploy.ps1
            interactive: true
            continueOnError: false

      ```
