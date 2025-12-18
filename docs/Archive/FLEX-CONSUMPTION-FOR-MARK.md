# Flex Consumption Deployment - Handover Document for Mark

**Author:** Previous Developer  
**Date:** December 17, 2025  
**Status:** Partially Complete - Manual Step Required

---

## Executive Summary

This document summarizes all work done to enable the Azure Document Processor (ADP) to run on **Azure Functions Flex Consumption plan**. Three issues were identified and addressed:

1. ✅ **Managed Identity (MI) Configuration** - FIXED (tells runtime which UAI to use for Key Vault)
2. ✅ **Blob Trigger Must Use EventGrid** - FIXED (Flex Consumption requires `source="EventGrid"`)
3. ⚠️ **Creating the EventGrid Subscription** - PARTIALLY FIXED (the subscription that sends blob events to the function - requires manual Portal step due to cold start timeout)

---

## Issue 1: Managed Identity Configuration

### Problem
Flex Consumption with User-Assigned Identity (UAI) only was failing because the Azure Functions runtime defaults to system-assigned identity for Key Vault references and internal operations. Without explicit configuration, the runtime couldn't authenticate.

### Root Cause
When using **UAI only** (no system-assigned identity), you MUST set `keyVaultReferenceIdentity` to tell the runtime which identity to use. This was missing.

### ✅ CODE CHANGE MADE

#### `infra/main.bicep` (Line ~1044)

**Added:**
```bicep
keyVaultAccessIdentityResourceId: uaiFrontendMsi.outputs.id
```

**Full context in the `processingFunctionApp` module call:**
```bicep
module processingFunctionApp 'br/public:avm/res/web/site:0.16.0' = {
  name: processingFunctionAppName
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

**Why:** This tells the Azure Functions runtime "use this specific UAI for Key Vault references" instead of defaulting to system-assigned identity (which doesn't exist in UAI-only configuration).

---

## Issue 2: Flex Consumption Blob Trigger Requirement

### Problem
Flex Consumption does NOT support polling-based blob triggers. It only supports EventGrid-based blob triggers.

### Root Cause
Traditional Azure Functions (Consumption/Dedicated plans) poll the storage account for new blobs. Flex Consumption eliminates polling to enable true scale-to-zero, so it requires EventGrid to push notifications when blobs are created.

### What This Means
For EventGrid-based blob triggers to work, you need **TWO things**:
1. **Code change:** Tell the function to expect EventGrid events (`source="EventGrid"`)
2. **Infrastructure:** Create an EventGrid subscription that sends blob events to the function

### ✅ CODE CHANGE MADE (Part 1 of 2)

#### `pipeline/function_app.py` (Line ~21-25)

**Changed from:**
```python
@app.blob_trigger(
    arg_name="blob",
    path="bronze/{name}",
    connection="DataStorage",
)
```

**Changed to:**
```python
@app.blob_trigger(
    arg_name="blob",
    path="bronze/{name}",
    connection="DataStorage",
    source="EventGrid",  # ← THIS WAS ADDED
)
```

**Why:** The `source="EventGrid"` parameter tells the blob trigger to expect notifications from EventGrid rather than polling. Without this, the function would never trigger on Flex Consumption.

---

## Issue 3: Creating the EventGrid Subscription (Part 2 of 2)

### The Connection to Issue 2
Issue 2 configured the function to **receive** EventGrid events. But someone still needs to **send** those events. That's what the EventGrid subscription does - it watches the storage account and pushes "blob created" events to the function's webhook endpoint.

### Why This Is Hard to Automate
Creating an EventGrid subscription with a webhook endpoint fails on Flex Consumption because:

1. Flex Consumption scales to **zero instances** when idle
2. EventGrid validates webhooks with ~30 second timeout
3. Cold starts on Flex Consumption can take 30-60+ seconds
4. The validation times out before the function wakes up

### What We Tried (All Failed)

| Approach | Result | Why |
|----------|--------|-----|
| `az eventgrid event-subscription create` (CLI) | ❌ Failed | 30s hardcoded timeout |
| Bicep/ARM deployment | ❌ Failed | Same validation timeout applies |
| Warmup HTTP requests before deploy | ❌ Failed | Function scales down during ARM deployment processing |
| Continuous warmup during deploy | ❌ Failed | Azure's validation uses different network path than our warmup |
| Background warmup jobs | ❌ Failed | Same as above |

### Key Finding
Two early test deployments (at 23:48 and 00:00 UTC) **succeeded** - but only because the function happened to be warm from active manual testing. All subsequent attempts failed once the function went cold.

**External warmup does NOT guarantee Azure's internal EventGrid validation will hit a warm instance.**

### ⚠️ CURRENT STATE: Best-Effort Automation with Manual Fallback

#### How the Automation Works (azure.yaml → postdeploy.ps1)

The `azd` CLI supports **hooks** - scripts that run at specific points during deployment. We use the `postdeploy` hook, which runs **after** function code is deployed.

**Why postdeploy and not during main Bicep deployment?**
The EventGrid webhook URL requires a `blobs_extension` system key. This key is generated by the Azure Functions blob extension **only after function code is deployed**. So we can't create the EventGrid subscription in main.bicep - the key doesn't exist yet.

**The chain:**
```
azd up
  └── azd provision (runs main.bicep - creates infrastructure)
  └── azd deploy (deploys function code - generates blobs_extension key)
  └── postdeploy hook (azure.yaml tells azd to run postdeploy.ps1)
        └── postdeploy.ps1 (attempts to create EventGrid subscription)
```

#### Change to `azure.yaml`

Added `postdeploy` hook that tells `azd` to run our script after code deployment:

```yaml
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

#### What `postdeploy.ps1` Does

This script attempts to create the EventGrid subscription:

1. **Load azd environment values** (storage account name, function app name, etc.)
2. **Check if subscription already exists** - skip if yes
3. **Get `blobs_extension` system key** from function app (required for webhook authentication)
4. **Build webhook URL**: `https://<function-app>.azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.start_orchestrator_on_blob&code=<blobs_extension_key>`
5. **Retry loop (3 attempts)**:
   - Send 5 HTTP warmup requests to the function
   - Deploy `blob-subscription.bicep` via `az deployment group create`
   - Wait 30 seconds if failed, then retry
6. **If all retries fail**: Exit with code 0 (so `azd up` completes successfully) and print Portal instructions

#### New File: `infra/modules/eventgrid/blob-subscription.bicep`

A new Bicep module that creates the EventGrid subscription. This folder and file do NOT exist in upstream.

**Location:** `infra/modules/eventgrid/blob-subscription.bicep`

**What it creates:** An EventGrid event subscription on the storage account that:
- Watches for `Microsoft.Storage.BlobCreated` events
- Filters to the `bronze` container only
- Sends events to the function's webhook endpoint

**Full content:**
```bicep
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

**How it's called (from postdeploy.ps1):**
```powershell
az deployment group create `
    --resource-group $env:AZURE_RESOURCE_GROUP `
    --template-file "infra/modules/eventgrid/blob-subscription.bicep" `
    --parameters storageAccountName=$env:AZURE_STORAGE_ACCOUNT `
                 webhookEndpoint=$webhookEndpoint `
                 subscriptionName="bronze-blob-trigger"
```

#### Files Summary

| File | Change | Purpose |
|------|--------|---------|
| `azure.yaml` | Modified | Added `postdeploy` hook to trigger the script |
| `scripts/postDeploy.ps1` | **Completely Replaced** | Was ~20 lines uploading prompts.yaml; now ~158 lines for EventGrid |
| `scripts/postDeploy.sh` | **Completely Replaced** | Was ~25 lines uploading prompts.yaml; now ~160 lines for EventGrid |
| `infra/modules/eventgrid/blob-subscription.bicep` | **New file** | Bicep module for the EventGrid subscription |

#### What `postDeploy.ps1` Was (Upstream Original)

The upstream version just uploaded a prompts file to storage:

```powershell
# Load azd environment values
azd env get-values | ForEach-Object { ... }

# Upload initial blob and prompt file
az storage blob upload --account-name $env:AZURE_STORAGE_ACCOUNT `
    --container-name "prompts" --name prompts.yaml `
    --file ./data/prompts.yaml --auth-mode login
```

**~20 lines total**

#### What `postDeploy.ps1` Is Now (Our Replacement)

Completely rewritten to create the EventGrid subscription:

```powershell
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

**~158 lines total**

**Note:** The original prompts.yaml upload functionality was NOT preserved. If prompts.yaml upload is needed, it should be added back or moved to postprovision.

---

## ⚠️ WHAT STILL NEEDS TO BE DONE

### Required Manual Step After `azd up`

If the postdeploy script fails (which it likely will on Flex Consumption), you must create the EventGrid subscription manually via Azure Portal:

1. **Navigate to:** Storage Account → Events → + Event Subscription

2. **Configure Event Subscription Details:**
   - Name: `bronze-blob-trigger`
   - Event Schema: Event Grid Schema
   - Filter to Event Types: **Blob Created** (uncheck all others)
   - Endpoint Type: **Azure Function**
   - Endpoint: Select `func-processing-<suffix>` → `start_orchestrator_on_blob`

3. **Configure Filters tab:**
   - Enable subject filtering: ✅ checked
   - Subject Begins With: `/blobServices/default/containers/bronze/`

4. **Click Create**

The Portal has internal retry logic and longer timeouts that work around the cold start issue.

### Guaranteed Automation Alternatives (NOT IMPLEMENTED)

If you need fully automated deployment, these options exist but were NOT implemented:

| Option | Trade-off | Implementation |
|--------|-----------|----------------|
| **Always Ready Instances** | Costs ~$50/month minimum | Add `alwaysReady: [{name: 'http', instanceCount: 1}]` to function app Bicep |
| **Use Consumption Plan** | Loses Flex Consumption benefits | Set `USE_FLEX = false` |
| **Use Dedicated Plan** | Higher cost | Set `USE_FLEX = false` |
| **Storage Queue destination** | Different trigger pattern | Requires code refactoring |

---

## File Reference

### Changed Files Summary

| File | Change Type | Description |
|------|-------------|-------------|
| `infra/main.bicep` | Modified | Added `keyVaultAccessIdentityResourceId` parameter |
| `pipeline/function_app.py` | Modified | Added `source="EventGrid"` to blob trigger |
| `azure.yaml` | Modified | Added `postdeploy` hook configuration |
| `infra/modules/eventgrid/blob-subscription.bicep` | **New** | Bicep module for EventGrid subscription |
| `scripts/postdeploy.ps1` | **New** | Windows post-deploy script |
| `scripts/postdeploy.sh` | **New** | Linux/Mac post-deploy script |

### Documentation Files

| File | Content |
|------|---------|
| `docs/FLEX-CONSUMPTION-MI-FIX.md` | Detailed MI root cause analysis |
| `docs/FLEX-CONSUMPTION-MI-FIX-EVENT-SUBSCRIPTION.md` | EventGrid automation gap analysis |
| `docs/FLEX-CONSUMPTION-EVENTGRID-PROBLEM.md` | Problem statement and attempted solutions |
| `docs/FLEX-CONSUMPTION-EVENTGRID-TROUBLESHOOTING-LOG.md` | Detailed testing log with 30+ attempts |

---

## Environment Information

| Environment | Hosting Plan | Status |
|-------------|--------------|--------|
| `adpf-ded` | Dedicated | ✅ Works fully automated |
| `adpf-flex` | Flex Consumption | ⚠️ Works with manual Portal step for EventGrid |

### Current Flex Deployment Resources

```
Resource Group: rg-adpf-flex
Function App: func-processing-qg73kli2bur62
Storage Account: stqg73kli2bur62data
Location: germanywestcentral
Subscription ID: 645dc499-096c-4a37-b6a9-cd12f8ac706e
```

---

## Testing the Deployment

1. Run `azd up` with Flex Consumption environment
2. If postdeploy script fails, follow the manual Portal steps above
3. Upload a PDF to the `bronze` container
4. Check `silver` container for processed output
5. Monitor via Log Stream in Azure Portal

### Key Function Names

| Function | Purpose |
|----------|---------|
| `start_orchestrator_on_blob` | Blob trigger - starts the orchestration |
| `start_orchestrator_http` | HTTP trigger - alternative entry point |
| `process_blob` | Orchestrator function |
| `runDocIntel` | Activity - Document Intelligence OCR |
| `callAoai` | Activity - Azure OpenAI processing |
| `writeToBlob` | Activity - Write output to silver container |

---

## Conclusion

The Flex Consumption deployment is **95% automated**. The only remaining manual step is creating the EventGrid webhook subscription via Azure Portal, which takes about 2 minutes.

This limitation is a known Azure platform issue with Flex Consumption + EventGrid webhook validation. Microsoft has not provided an automated solution that handles cold start timeouts.

**For questions, see the detailed documentation in the `docs/FLEX-CONSUMPTION-*.md` files.**

---

## Appendix: Complete Diff from Upstream Azure Repo

This section documents every change made from the official upstream repository:
- **Upstream:** `https://github.com/Azure/ai-document-processor`
- **Origin (fork):** `https://github.com/jamesearlpace/ai-document-processor`

### Summary of Changes

| File | Status | Description |
|------|--------|-------------|
| `infra/main.bicep` | **MODIFIED** | +1 line: Added `keyVaultAccessIdentityResourceId` |
| `pipeline/function_app.py` | **MODIFIED** | +1 line: Added `source="EventGrid"` |
| `azure.yaml` | **MODIFIED** | +8 lines: Added `postdeploy` hook with shell/run/interactive/continueOnError |
| `infra/modules/eventgrid/blob-subscription.bicep` | **NEW FILE** | Created EventGrid subscription Bicep module |
| `scripts/postDeploy.ps1` | **REPLACED** | Original uploaded prompts.yaml; now creates EventGrid subscription |
| `scripts/postDeploy.sh` | **REPLACED** | Original uploaded prompts.yaml; now creates EventGrid subscription |
| `docs/FLEX-CONSUMPTION-*.md` | **NEW FILES** | 5 documentation files created |

---

### Change 1: `infra/main.bicep`

**Location:** Line ~1044, inside the `processingFunctionApp` module call

**UPSTREAM (original):**
```bicep
module processingFunctionApp 'br/public:avm/res/web/site:0.16.0' = {
  name: processingFunctionAppName
  params: {
    kind: 'functionapp,linux'
    name: processingFunctionAppName
    location: location
    tags: union(tags , { 'azd-service-name' : 'processing' })
    serverFarmResourceId: hostingPlan.outputs.resourceId
    httpsOnly: true
    managedIdentities: {
        systemAssigned: false
        userAssignedResourceIds: [
          uaiFrontendMsi.outputs.id
        ]
    }
    // ... rest of params
```

**LOCAL (modified):**
```bicep
module processingFunctionApp 'br/public:avm/res/web/site:0.16.0' = {
  name: processingFunctionAppName
  params: {
    kind: 'functionapp,linux'
    name: processingFunctionAppName
    location: location
    tags: union(tags , { 'azd-service-name' : 'processing' })
    serverFarmResourceId: hostingPlan.outputs.resourceId
    httpsOnly: true
    keyVaultAccessIdentityResourceId: uaiFrontendMsi.outputs.id  // ← ADDED THIS LINE
    managedIdentities: {
        systemAssigned: false
        userAssignedResourceIds: [
          uaiFrontendMsi.outputs.id
        ]
    }
    // ... rest of params
```

**Why:** When using UAI-only (no system-assigned MI), Azure Functions runtime needs to know which identity to use for Key Vault references. Without this, it defaults to system-assigned MI which doesn't exist.

---

### Change 2: `pipeline/function_app.py`

**Location:** Lines 20-25, the `@app.blob_trigger` decorator

**UPSTREAM (original):**
```python
@app.blob_trigger(
    arg_name="blob",
    path="bronze/{name}",
    connection="DataStorage",
)
```

**LOCAL (modified):**
```python
@app.blob_trigger(
    arg_name="blob",
    path="bronze/{name}",
    connection="DataStorage",
    source="EventGrid",  // ← ADDED THIS LINE
)
```

**Why:** Flex Consumption only supports EventGrid-based blob triggers, not polling-based triggers. This tells the runtime to use EventGrid for blob change notifications.

---

### Change 3: `azure.yaml`

**Location:** End of file, `hooks` section

**UPSTREAM (original):**
```yaml
hooks:
  postprovision:
    posix:
      run: scripts/postprovision.sh
    windows:
      run: scripts/postprovision.ps1
  # postdeploy:
  #   posix:
  #     run: scripts/postDeploy.sh
  #   windows:
  #     run: scripts/postDeploy.ps1
```

**LOCAL (modified):**
```yaml
hooks:
  postprovision:
    posix:
      run: scripts/postprovision.sh
    windows:
      run: scripts/postprovision.ps1
  postdeploy:
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

**Why:** Added postdeploy hook to attempt EventGrid subscription creation after function code is deployed. The commented-out postdeploy in upstream was enabled and expanded with shell/interactive/continueOnError options.

---

### Change 4: `infra/modules/eventgrid/blob-subscription.bicep` (NEW FILE)

**Status:** This is a completely new file. The `infra/modules/eventgrid/` directory does not exist in upstream.

**Content summary:**
- Creates an EventGrid event subscription on a storage account
- Filters to `Microsoft.Storage.BlobCreated` events
- Filters to `/blobServices/default/containers/bronze/` path
- Uses webhook endpoint to Azure Function

**Full file location:** `infra/modules/eventgrid/blob-subscription.bicep`

---

### Change 5: `scripts/postDeploy.ps1` (REPLACED)

**UPSTREAM (original purpose):** Upload prompts.yaml to storage account

**UPSTREAM code (simplified):**
```powershell
# Load azd environment values
azd env get-values | ForEach-Object { ... }

# Upload initial blob and prompt file
az storage blob upload --account-name $env:AZURE_STORAGE_ACCOUNT `
    --container-name "prompts" --name prompts.yaml `
    --file ./data/prompts.yaml --auth-mode login
```

**LOCAL (replacement):** Full EventGrid subscription creation with:
- Check if subscription already exists
- Get `blobs_extension` system key from function app
- Build webhook URL with authentication
- 3-retry loop with warmup HTTP requests between attempts
- Bicep deployment for subscription creation
- Graceful failure with Portal instructions on timeout

**File size change:** ~20 lines → ~158 lines

---

### Change 6: `scripts/postDeploy.sh` (REPLACED)

**UPSTREAM (original purpose):** Upload prompts.yaml to storage account

**UPSTREAM code (simplified):**
```bash
#!/bin/bash
eval "$(azd env get-values)"
az storage blob upload \
    --account-name $AZURE_STORAGE_ACCOUNT \
    --container-name "prompts" \
    --name prompts.yaml \
    --file ./data/prompts.yaml \
    --auth-mode login
```

**LOCAL (replacement):** Same as PowerShell version - full EventGrid subscription creation with retry logic.

**File size change:** ~25 lines → ~160 lines

---

### Change 7: Documentation Files (NEW)

All of these are new files that don't exist in upstream:

| File | Purpose |
|------|---------|
| `docs/FLEX-CONSUMPTION-MI-FIX.md` | Root cause analysis of Managed Identity issue |
| `docs/FLEX-CONSUMPTION-MI-FIX-EVENT-SUBSCRIPTION.md` | EventGrid automation gap analysis |
| `docs/FLEX-CONSUMPTION-EVENTGRID-PROBLEM.md` | Problem statement and attempted solutions |
| `docs/FLEX-CONSUMPTION-EVENTGRID-TROUBLESHOOTING-LOG.md` | Detailed log of 30+ deployment attempts |
| `docs/FLEX-CONSUMPTION-FOR-MARK.md` | This handover document |

---

### Files NOT Changed (Unchanged from Upstream)

The following key files were examined but **NOT modified**:
- `infra/modules/security/managed-identity.bicep` - unchanged
- `infra/modules/security/key-vault.bicep` - unchanged
- `infra/modules/app_config/appconfig.bicep` - unchanged
- `infra/modules/storage/storage-account.bicep` - unchanged
- `pipeline/activities/*.py` - all unchanged
- `pipeline/configuration.py` - unchanged
- `requirements.txt` - unchanged

---

### How to Verify Changes with Git

```bash
# See all modified files
git status

# Compare with upstream
git remote add upstream https://github.com/Azure/ai-document-processor (if not already added)
git fetch upstream
git diff upstream/main -- infra/main.bicep
git diff upstream/main -- pipeline/function_app.py
git diff upstream/main -- azure.yaml
git diff upstream/main -- scripts/postDeploy.ps1
git diff upstream/main -- scripts/postDeploy.sh

# List new files not in upstream
git diff upstream/main --name-status | grep "^A"
```

---

*Last Updated: December 17, 2025*
