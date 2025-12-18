# Flex Consumption Plan - Managed Identity Configuration Fix

## Document Purpose
This document describes the root cause analysis and fix plan for the Managed Identity issue preventing successful deployment of the Azure Document Processor to Azure Functions Flex Consumption plan with EventGrid blob triggers.

---

## Executive Summary

The Flex Consumption deployment fails because the Function App is configured with **User-Assigned Identity (UAI) only**, but the Azure Functions runtime expects the `keyVaultReferenceIdentity` property to be explicitly set when using UAI. Without this property, the runtime defaults to looking for a system-assigned identity (which doesn't exist), causing storage access failures.

---

## Problem Description

### Observed Behavior
When deploying to Flex Consumption plan:
1. Deployment appears to complete successfully
2. Function App starts but cannot access storage
3. EventGrid blob triggers do not fire
4. Runtime errors related to managed identity authentication

### Environment Details
- **Working Configuration:** Dedicated/Premium plan (`adpf-ded` environment)
- **Failing Configuration:** Flex Consumption plan (`adpf-flex` environment)
- **Key Difference:** Flex Consumption requires EventGrid-based blob triggers and has stricter MI requirements

---

## Root Cause Analysis

### Key Documentation Finding

From [Microsoft Docs - Identity-Based Connections Tutorial](https://learn.microsoft.com/en-us/azure/azure-functions/functions-identity-based-connections-tutorial):

> **"You need this configuration because an app could have multiple user-assigned identities configured. Whenever you want to use a user-assigned identity, you must specify it with an ID. System-assigned identities don't need to be specified this way, because an app can only ever have one. Many features that use managed identity assume they should use the system-assigned one by default."**

From [Microsoft Docs - Key Vault References](https://learn.microsoft.com/en-us/azure/app-service/app-service-key-vault-references):

> **"Key vault references use the app's system-assigned identity by default, but you can specify a user-assigned identity."**
>
> **"Configure the app to use this identity for Key Vault reference operations by setting the `keyVaultReferenceIdentity` property to the resource ID of the user-assigned identity."**

### Current Bicep Configuration Analysis

**File:** `infra/main.bicep`

#### Identity Configuration (Lines 1044-1047)
```bicep
managedIdentities: {
  systemAssigned: false
  userAssignedResourceIds: [uaiFrontendMsi.outputs.id]
}
```
- ❌ System-assigned identity is explicitly disabled
- ✅ User-assigned identity is configured
- ❌ **Missing:** `keyVaultReferenceIdentity` is not set

#### Deployment Storage Configuration (Lines 1050-1062)
```bicep
functionAppConfig: {
  deployment: {
    storage: {
      type: 'blobContainer'
      value: '${procFuncStorage.outputs.primaryBlobEndpoint}deploymentpackage'
      authentication: {
        type: 'UserAssignedIdentity'
        userAssignedIdentityResourceId: uaiFrontendMsi.outputs.id
      }
    }
  }
  // ...
}
```
- ✅ Deployment storage correctly specifies UAI
- ❌ Runtime doesn't know to use UAI for other operations

#### App Settings (Lines 985-1005)
```bicep
var commonAppSettings = [
  { name: 'AzureWebJobsStorage__accountName', value: procFuncStorage.outputs.name }
  { name: 'AzureWebJobsStorage__credential', value: 'managedidentity' }
  { name: 'AzureWebJobsStorage__clientId', value: uaiFrontendMsi.outputs.clientId }
  { name: 'DataStorage__credential', value: 'managedidentity' }
  { name: 'DataStorage__clientId', value: uaiFrontendMsi.outputs.clientId }
  // ...
]
```
- ✅ Storage connections correctly specify clientId for UAI
- ❌ Not sufficient for all runtime operations that assume system identity

### The Core Problem

```
┌─────────────────────────────────────────────────────────────────┐
│                    Azure Functions Runtime                       │
├─────────────────────────────────────────────────────────────────┤
│  When performing identity-based operations:                      │
│                                                                  │
│  1. Check if keyVaultReferenceIdentity is set                   │
│     └─> NOT SET in current config                               │
│                                                                  │
│  2. Fall back to system-assigned identity                       │
│     └─> DOESN'T EXIST (systemAssigned: false)                   │
│                                                                  │
│  3. Operation FAILS                                              │
└─────────────────────────────────────────────────────────────────┘
```

---

## Why User-Assigned Identity Was Chosen (Do Not Change)

The UAI architecture is intentional and should be preserved:

1. **Pre-provisioning:** Role assignments can be created before the Function App exists
2. **Shared Identity:** Same identity used across multiple resources (Function App, potentially others)
3. **IaC Compatibility:** Avoids chicken-and-egg deployment ordering issues
4. **Existing Role Assignments:** All RBAC is configured for the UAI:
   - Storage Blob Data Owner on `procFuncStorage`
   - Cognitive Services OpenAI User
   - Key Vault Secrets User
   - Queue Data Contributor
   - etc.

**⚠️ Switching to system-assigned identity would break all existing role assignments and require significant refactoring.**

---

## Investigation History

### What Was Tried

1. **Initial Deployment Attempt**
   - Attempted `azd up` with Flex Consumption
   - Failed with storage access errors

2. **Dedicated Plan Workaround**
   - Created `adpf-ded` environment with `USE_FLEX = false`
   - Deployment succeeded
   - Confirmed application works correctly

3. **Documentation Research**
   - Reviewed Azure Functions Flex Consumption documentation
   - Reviewed AVM module documentation for `br/public:avm/res/web/site`
   - Reviewed Microsoft identity-based connections tutorials
   - **Found the critical documentation about `keyVaultReferenceIdentity`**

4. **Azure Samples Analysis**
   - Reviewed `Azure-Samples/azure-functions-flex-consumption-samples`
   - Found that official samples use `systemAssigned: true`
   - Confirmed this is why those samples work without additional config

---

## Required Changes

### Change 1: ✅ COMPLETED - Add `keyVaultAccessIdentityResourceId` to Function App

**File:** `infra/main.bicep` - `processingFunctionApp` module call (line ~1044)

**Added:**
```bicep
keyVaultAccessIdentityResourceId: uaiFrontendMsi.outputs.id
```

This tells the Azure Functions runtime to use the User-Assigned Identity for Key Vault references and other identity-based operations.

### Change 2: ✅ COMPLETED - Add EventGrid Source to Blob Trigger

**Critical:** The documentation states "the Flex Consumption plan supports only the event-based Blob storage trigger."

**File:** `pipeline/function_app.py` - blob trigger decorator (line ~21)

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
    source="EventGrid",  # Required for Flex Consumption!
)
```

### Change 3: EventGrid Subscription - MANUAL STEP AFTER DEPLOYMENT

After deploying the function app, you may need to create an EventGrid subscription manually:

1. Go to the storage account in Azure Portal
2. Navigate to **Events**
3. Click **+ Event Subscription**
4. Configure:
   - Name: `bronze-blob-created`
   - Event Schema: Event Grid Schema
   - Filter to Event Types: **Blob Created**
   - Endpoint Type: **Web Hook**
   - Endpoint: `https://<FUNCTION_APP_NAME>.azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.start_orchestrator_on_blob&code=<BLOB_EXTENSION_KEY>`

To get the `<BLOB_EXTENSION_KEY>`:
1. Go to Function App → **App keys** → **System keys**
2. Copy the value of `blobs_extension`

**Note:** Azure may auto-create this subscription if the function app has appropriate permissions.

---

## Implementation Steps

### Step 1: Locate the AVM Module Parameter

Search the AVM module documentation or source for `keyVaultReferenceIdentity`:
- GitHub: https://github.com/Azure/bicep-registry-modules/blob/main/avm/res/web/site/README.md
- Look in the parameters table for the exact parameter name

### Step 2: Update main.bicep

Add the `keyVaultReferenceIdentity` parameter to the `processingFunctionApp` module call.

### Step 3: Test Deployment

```powershell
# Set environment to flex
azd env select adpf-flex

# Deploy
azd up
```

### Step 4: Verify EventGrid Trigger

After deployment, upload a test file and verify the trigger fires.

---

## Reference Links

1. **Key Vault References Documentation**
   - https://learn.microsoft.com/en-us/azure/app-service/app-service-key-vault-references

2. **Identity-Based Connections Tutorial**
   - https://learn.microsoft.com/en-us/azure/azure-functions/functions-identity-based-connections-tutorial

3. **AVM Web Site Module**
   - https://github.com/Azure/bicep-registry-modules/blob/main/avm/res/web/site/README.md

4. **Flex Consumption Blob Triggers**
   - https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-storage-blob-trigger?tabs=python-v2#event-grid-extension

5. **Azure Functions Flex Consumption Samples**
   - https://github.com/Azure-Samples/azure-functions-flex-consumption-samples

---

## Appendix: Full Context for Future Sessions

### Files to Examine
- `infra/main.bicep` - Main infrastructure definition
- `infra/modules/security/managed-identity.bicep` - UAI module
- `pipeline/function_app.py` - Function definitions

### Key Search Terms
- `keyVaultReferenceIdentity`
- `uaiFrontendMsi`
- `managedIdentities`
- `processingFunctionApp`

### Environment Status
- `adpf-ded` - Dedicated plan, working correctly
- `adpf-flex` - Flex Consumption, needs fix described above

### Test Files
- `pipeline/testdocs/PaceFamilyHistoryShort.pdf` - Known working test document
