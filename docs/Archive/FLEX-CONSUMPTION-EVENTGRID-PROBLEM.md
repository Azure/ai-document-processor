# Azure Functions Flex Consumption + EventGrid: CLI Webhook Validation Failure

## Problem Statement

**When using Azure Functions on the Flex Consumption plan with EventGrid-based blob triggers, the `az eventgrid event-subscription create` CLI command fails with a webhook validation error, even when the function is fully deployed and running.**

## Error Message

```
(URL validation) Webhook validation handshake failed for 
https://<function-app>.azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.<function>&code=<key>
Http POST request failed with response code Unknown.
```

## Environment

| Component | Value |
|-----------|-------|
| Function App | `func-processing-qg73kli2bur62` |
| Hosting Plan | **Flex Consumption** |
| Trigger Type | Blob trigger with `source="EventGrid"` |
| Storage Account | `stqg73kli2bur62data` |
| Resource Group | `rg-adpf-flex` |

## Reproduction Steps

1. Deploy Azure Functions app to Flex Consumption plan
2. Function uses blob trigger with `source="EventGrid"` annotation
3. Attempt to create EventGrid subscription via CLI:

```powershell
$blobsKey = az functionapp keys list --name <app> --resource-group <rg> --query "systemKeys.blobs_extension" -o tsv
$webhookUrl = "https://<app>.azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.<func>&code=$blobsKey"

az eventgrid event-subscription create `
    --name bronze-blob-trigger `
    --source-resource-id "/subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Storage/storageAccounts/<storage>" `
    --endpoint-type webhook `
    --endpoint $webhookUrl `
    --included-event-types Microsoft.Storage.BlobCreated `
    --subject-begins-with /blobServices/default/containers/bronze/
```

4. **Result**: Webhook validation handshake fails

## Root Cause Analysis

### The Flex Consumption Cold Start Problem

Flex Consumption apps scale to zero when idle. When EventGrid sends the validation POST request:

1. **CLI timeout**: The Azure CLI has a short, non-configurable timeout for webhook validation (~30 seconds)
2. **Cold start delay**: Flex Consumption cold start can take 30-60+ seconds
3. **Race condition**: The validation request times out before the function wakes up and responds

### Why Azure Portal Works

The Azure Portal uses a different validation flow:
- Longer timeout window
- Automatic retry logic
- Asynchronous validation with polling

### Timing is NOT the Issue

We tested creating the subscription **after** the function was fully deployed and had been running. The CLI still fails because:
- The function scales to zero between deployments/tests
- Each CLI attempt hits a cold function
- There's no way to "warm up" the function before CLI validation starts

## Attempted Solutions

| Approach | Result |
|----------|--------|
| `postprovision` hook (before code deploy) | ❌ Failed - function not deployed yet |
| `postdeploy` hook (after code deploy) | ❌ Failed - function cold, same timeout |
| Manual CLI after `azd up` completes | ❌ Failed - function cold, same timeout |
| Microsoft's `functions-e2e-blob-pdf-to-text` pattern | ❌ Uses same CLI approach, would fail on Flex |

## Current Workaround

**Manual creation via Azure Portal is the only reliable method.**

1. Navigate to Storage Account → Events → Event Subscriptions
2. Create subscription with webhook endpoint
3. Portal handles validation with retries/longer timeout

## Potential Solutions (Not Yet Tested)

### 1. Pre-warm the Function
```powershell
# Hit a health endpoint to wake up the function before CLI
Invoke-WebRequest -Uri "https://<app>.azurewebsites.net/api/health" -TimeoutSec 120
Start-Sleep -Seconds 10
# Then run az eventgrid event-subscription create
```

### 2. Use Always Ready Instances
Configure minimum instances in Flex Consumption to prevent cold starts:
```bicep
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  properties: {
    functionAppConfig: {
      scaleAndConcurrency: {
        alwaysReady: [
          {
            name: 'http'
            instanceCount: 1
          }
        ]
      }
    }
  }
}
```
**Downside**: Increases cost, defeats purpose of Flex Consumption

### 3. Bicep/ARM Instead of CLI
Create EventGrid subscription via Bicep with explicit dependencies:
```bicep
resource eventSubscription 'Microsoft.EventGrid/eventSubscriptions@2024-06-01-preview' = {
  name: 'bronze-blob-trigger'
  scope: storageAccount
  dependsOn: [functionApp]  // May not help with cold start
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: webhookUrl
      }
    }
  }
}
```
**Status**: Untested - may have same validation timeout issue

### 4. Managed Identity with System Topic
Use EventGrid System Topic with managed identity instead of webhook:
- Avoids webhook validation entirely
- More complex setup
- Different trigger binding configuration

## Impact

- **Automation Gap**: Cannot fully automate Flex Consumption + EventGrid deployments
- **DevOps Friction**: Manual Portal step required after every environment creation
- **CI/CD Limitation**: Pipelines cannot be fully automated

## References

- [Azure EventGrid Webhook Validation](https://aka.ms/eg-webhook-endpoint-validation)
- [Azure Functions Blob Trigger with EventGrid](https://learn.microsoft.com/en-us/azure/azure-functions/functions-event-grid-blob-trigger)
- [Flex Consumption Plan Overview](https://learn.microsoft.com/en-us/azure/azure-functions/flex-consumption-plan)
- [Microsoft Sample: functions-e2e-blob-pdf-to-text](https://github.com/Azure-Samples/functions-e2e-blob-pdf-to-text)

## Status

**UNRESOLVED** - Awaiting Microsoft fix or discovery of reliable workaround.

---
*Last Updated: December 16, 2025*
*Tested By: Azure Document Processor team*
