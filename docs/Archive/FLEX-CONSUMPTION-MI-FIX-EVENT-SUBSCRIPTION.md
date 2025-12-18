# Azure Functions Flex Consumption + EventGrid Blob Trigger: The Automation Gap

## Update (December 2025): SOLVED

**This issue has been resolved.** The original analysis below was based on using the wrong `azd` hook timing. Microsoft's official samples demonstrate that full automation IS possible using the `postdeploy` hook instead of `postprovision`.

### The Fix

The key insight from [Microsoft's official PDF-to-text sample](https://github.com/Azure-Samples/functions-e2e-blob-pdf-to-text):

1. **Use `postdeploy` hook** (runs AFTER code deployment), not `postprovision` (runs BEFORE)
2. By the time `postdeploy` runs, the function code is deployed and the blob extension is initialized
3. The `blobs_extension` key is available via `az functionapp keys list`
4. The webhook validation succeeds because the function is fully operational

### Implementation

```yaml
# azure.yaml
hooks:
  postdeploy:
    windows:
      shell: pwsh
      run: scripts/postdeploy.ps1
      interactive: true
      continueOnError: false
```

```powershell
# scripts/postdeploy.ps1
$blobsExtensionKey = az functionapp keys list --name $functionAppName --resource-group $env:AZURE_RESOURCE_GROUP --query "systemKeys.blobs_extension" -o tsv

$webhookEndpoint = "https://$functionAppName.azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.start_orchestrator_on_blob&code=$blobsExtensionKey"

az eventgrid event-subscription create `
    --name bronze-blob-trigger `
    --source-resource-id $storageResourceId `
    --endpoint $webhookEndpoint `
    --endpoint-type webhook `
    --included-event-types Microsoft.Storage.BlobCreated `
    --subject-begins-with /blobServices/default/containers/bronze/
```

---

## Original Problem Analysis (Historical Reference)

### What We're Trying to Do

Deploy an Azure Functions app on the **Flex Consumption** hosting plan that:
1. Uses **User-Assigned Managed Identity** (UAI) for all authentication
2. Triggers on blob uploads via **EventGrid-based blob trigger** (required for Flex Consumption)
3. Is **fully automated** via `azd up`, Bicep, or equivalent IaC

### What Works

| Component | Status | Method |
|-----------|--------|--------|
| Function App (Flex Consumption) | ✅ Works | Bicep/azd |
| User-Assigned Managed Identity | ✅ Works | Bicep/azd |
| Storage Account with containers | ✅ Works | Bicep/azd |
| Key Vault with UAI access | ✅ Works | Bicep/azd |
| EventGrid System Topic | ✅ Works | Bicep/azd |
| Function code with `source="EventGrid"` | ✅ Works | azd deploy |
| **EventGrid Webhook Subscription** | ❌ **FAILS** | CLI/Bicep/ARM |
| **EventGrid Webhook Subscription** | ✅ Works | **Portal only** |

### What Fails

Creating an EventGrid subscription with a **WebHook endpoint** pointing to the Azure Functions blob extension endpoint:

```
https://<function-app>.azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.<function-name>&code=<blob-extension-key>
```

---

## Root Cause Analysis

### The Validation Handshake

When creating an EventGrid subscription with a WebHook endpoint, Azure EventGrid performs a **validation handshake**:

1. EventGrid sends an HTTP POST to the webhook URL with a `SubscriptionValidation` event
2. The endpoint must respond with a `validationResponse` containing the validation code
3. Only after successful validation does EventGrid create the subscription

**Reference:** [Webhook event delivery - Microsoft Learn](https://learn.microsoft.com/en-us/azure/event-grid/webhook-event-delivery)

### Why Azure CLI Fails

```bash
az eventgrid event-subscription create \
  --name my-subscription \
  --source-resource-id /subscriptions/.../storageAccounts/mystorageaccount \
  --endpoint https://myfunc.azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.myTrigger&code=xxx \
  --endpoint-type webhook
```

**Result:**
```
Webhook validation handshake failed for https://myfunc.azurewebsites.net/...
Reason: response code Unknown. If this is an Azure Function, please make sure it is running.
```

**Why it happens:**

| Factor | Impact |
|--------|--------|
| **Synchronous validation** | CLI waits synchronously for validation with ~30 second timeout |
| **Flex Consumption cold start** | Instances scale to zero; first request requires cold start |
| **Cold start duration** | Can exceed 30+ seconds for Python apps with dependencies |
| **No retry logic** | CLI makes one attempt; if it times out, it fails |
| **Blob extension initialization** | The `/runtime/webhooks/blobs` endpoint has its own initialization path separate from HTTP triggers |

### Why Bicep/ARM Fails

```bicep
resource eventSubscription 'Microsoft.EventGrid/systemTopics/eventSubscriptions@2022-06-15' = {
  parent: systemTopic
  name: 'blob-trigger'
  properties: {
    destination: {
      endpointType: 'WebHook'
      properties: {
        endpointUrl: 'https://myfunc.azurewebsites.net/runtime/webhooks/blobs?...'
      }
    }
  }
}
```

**Result:** Same validation timeout failure. ARM deployments also use synchronous validation.

**Additional Bicep limitation:** You cannot reference the blob extension key dynamically in Bicep because:
- The key is only available after the Function App is deployed and running
- `listKeys()` doesn't expose system keys like `blobs_extension`
- There's no Bicep function to retrieve extension webhook keys

### Why Azure Portal Works

The Azure Portal uses a **different validation flow**:

1. **Asynchronous validation** with longer timeout (up to 5 minutes)
2. **Automatic retries** with exponential backoff
3. **Better status polling** - waits for validation to complete
4. **User-facing progress indicator** that masks the retry behavior

The Portal's JavaScript client uses undocumented APIs or internal retry logic that is **not available** through:
- Azure CLI
- Azure PowerShell
- ARM/Bicep templates
- REST API direct calls

---

## What We've Tried

### Attempt 1: Pre-warming with HTTP calls
```powershell
# Warm up the function before creating subscription
1..10 | % { Invoke-WebRequest -Uri "https://myfunc.azurewebsites.net/api/health" -Method GET }
Start-Sleep -Seconds 30
az eventgrid event-subscription create ...
```
**Result:** ❌ Still fails. HTTP trigger warming doesn't warm the blob extension endpoint.

### Attempt 2: Always Ready Instances for HTTP
```bicep
functionAppScaleAndConcurrency: {
  alwaysReady: [{ name: 'http', instanceCount: 1 }]
}
```
**Result:** ❌ Still fails. `http` group doesn't include the blob extension webhook handler.

### Attempt 3: Always Ready Instances for Blob
```bicep
functionAppScaleAndConcurrency: {
  alwaysReady: [{ name: 'blob', instanceCount: 1 }]
}
```
**Result:** ❌ Still fails. The `blob` always-ready keeps blob trigger processing warm, but the **webhook validation endpoint** still requires initialization on first call.

### Attempt 4: Manual Webhook Testing
```powershell
# Test OPTIONS request (CloudEvents validation)
Invoke-WebRequest -Uri $webhookUrl -Method OPTIONS
# Result: 200 OK ✅

# Test POST with validation event
Invoke-WebRequest -Uri $webhookUrl -Method POST -Headers @{"aeg-event-type"="SubscriptionValidation"} -Body $validationEvent
# Result: 200 OK with validationResponse ✅
```
**Result:** Manual tests succeed! But EventGrid's infrastructure still times out.

### Attempt 5: Storage Queue Endpoint Instead of WebHook
```powershell
az eventgrid event-subscription create \
  --endpoint-type storagequeue \
  --endpoint /subscriptions/.../storageAccounts/mystorageaccount/queueServices/default/queues/eventgrid-events
```
**Result:** ✅ Works! No validation handshake required.

**But:** This creates a queue-based trigger, not a direct blob trigger. Requires additional function to process queue messages.

### Attempt 6: Retry Loop in Post-Provision Script
```powershell
$maxAttempts = 10
for ($i = 1; $i -le $maxAttempts; $i++) {
    # Warm up
    Invoke-WebRequest -Uri $webhookUrl -Method OPTIONS -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 10
    
    # Try to create subscription
    $result = az eventgrid event-subscription create ... 2>&1
    if ($LASTEXITCODE -eq 0) { break }
    
    Start-Sleep -Seconds 30
}
```
**Result:** ❌ Fails all 10 attempts. The timing window is too narrow and unpredictable.

---

## The Fundamental Gap

### What Microsoft Provides

| Feature | Documentation | Automation Support |
|---------|--------------|-------------------|
| Flex Consumption Plan | ✅ Documented | ✅ Bicep/CLI |
| EventGrid Blob Trigger | ✅ Documented | ⚠️ Portal tutorial only |
| EventGrid Webhook Validation | ✅ Documented | ❌ No retry/async API |
| Always Ready Instances | ✅ Documented | ✅ Bicep/CLI |
| Blob Extension Key | ❌ Not exposed | ❌ No `listKeys()` support |

### What Microsoft Doesn't Provide

1. **Asynchronous EventGrid subscription creation API** with built-in retry
2. **ARM/Bicep function to retrieve blob extension key** (`blobs_extension`)
3. **Pre-provisioning hook** to ensure function is warm before subscription creation
4. **Configurable validation timeout** for EventGrid webhook subscriptions
5. **Documentation acknowledging this limitation** for Flex Consumption + EventGrid

---

## Impact

### Who Is Affected

Any organization that wants to:
- Use Flex Consumption for cost efficiency
- Process blob uploads with low latency (EventGrid, not polling)
- Maintain proper security (Managed Identity, no connection strings)
- Automate infrastructure deployment (IaC, GitOps, CI/CD)

### Current Workarounds (All Unsatisfactory)

| Workaround | Downside |
|------------|----------|
| Use Azure Portal | Manual step, not automatable, breaks IaC |
| Use Consumption Plan instead | Loses Flex Consumption benefits (VNet, instance control) |
| Use Dedicated Plan | Higher cost, defeats serverless purpose |
| Use polling-based blob trigger | Higher latency, not supported on Flex Consumption |
| Use Storage Queue intermediate | Additional complexity, two-step processing |
| Post-deployment manual step | Breaks fully automated deployment |

---

## What Microsoft Needs to Fix

### Option A: Async Subscription Creation API
Provide an ARM/CLI option for asynchronous subscription creation:
```bash
az eventgrid event-subscription create ... --validation-mode async --validation-timeout 300
```

### Option B: Expose Blob Extension Key in ARM
Allow `listKeys()` to return system keys including `blobs_extension`:
```bicep
var blobExtensionKey = listKeys(functionApp.id, '2023-12-01').systemKeys.blobs_extension
```

### Option C: Built-in EventGrid Integration for Flex Consumption
When creating a Flex Consumption app with blob triggers, automatically provision the EventGrid subscription as part of the function app deployment.

### Option D: Pre-warm Guarantee
Provide a deployment setting that guarantees the function app is fully initialized before ARM deployment completes:
```bicep
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  properties: {
    ensureWarmOnDeploy: true  // Wait for all extensions to initialize
  }
}
```

---

## Current Status

**Date:** December 2025

**Deployment Environment:**
- Azure Functions Flex Consumption Plan
- Python 3.11
- User-Assigned Managed Identity
- Germany West Central region
- EventGrid System Topic created successfully
- Function app deployed and running

**Working Solution:**
- EventGrid subscription created **manually via Azure Portal**
- Blob trigger fires successfully
- Document processing pipeline works end-to-end

**Blocked:**
- Full IaC automation
- CI/CD without manual intervention
- True infrastructure-as-code deployment

---

## References

- [Azure Functions Flex Consumption Plan](https://learn.microsoft.com/en-us/azure/azure-functions/flex-consumption-plan)
- [Tutorial: Trigger Azure Functions on blob containers using event subscription](https://learn.microsoft.com/en-us/azure/azure-functions/functions-event-grid-blob-trigger)
- [Webhook Event Delivery](https://learn.microsoft.com/en-us/azure/event-grid/webhook-event-delivery)
- [Create and manage function apps in Flex Consumption](https://learn.microsoft.com/en-us/azure/azure-functions/flex-consumption-how-to)
- [Flex Consumption IaC Samples](https://github.com/Azure-Samples/azure-functions-flex-consumption-samples)

---

## Conclusion

~~The Azure Functions Flex Consumption plan with EventGrid-based blob triggers is a powerful combination for serverless document processing. However, **Microsoft has created a gap between the documented architecture and automatable deployment**.~~

**UPDATE:** Full automation IS possible using the correct hook timing. The key is using `postdeploy` (after code deployment) instead of `postprovision` (after infrastructure only). Microsoft's official samples at [functions-e2e-blob-pdf-to-text](https://github.com/Azure-Samples/functions-e2e-blob-pdf-to-text) demonstrate this pattern.

### Lessons Learned

1. **Hook timing matters**: `postprovision` runs before code deploy; `postdeploy` runs after
2. **The blob extension must be initialized**: This only happens after function code is deployed
3. **Microsoft's samples are the source of truth**: Always check official sample repos for patterns
4. **The CLI works fine**: The validation timeout was because we were calling it too early

---

*This document was created to track the technical limitations encountered during deployment of the Azure Document Processor solution on Flex Consumption. Updated to reflect the solution discovered via Microsoft's official samples.*
