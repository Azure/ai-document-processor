# Fix: Configurable VM Size via Environment Variable

## Background

The AI Document Processor can optionally deploy a **Windows 11 jumpbox VM** with Azure Bastion. This VM is only created when **both** of the following conditions are true:

- `AZURE_DEPLOY_VM=true`
- `AZURE_NETWORK_ISOLATION=true`

The VM exists so users can access resources from inside the private VNet when network isolation is enabled (all services are locked down with Private Endpoints and have no public internet access). Without both flags enabled, **no VM is created** — this is expected behavior.

## Problem

The Bicep template (`infra/main.bicep`) already had a `vmSize` parameter with a hardcoded default of `Standard_D8s_v5`:

```bicep
@description('Size of the test VM')
param vmSize string = 'Standard_D8s_v5'
```

However, none of the deployment scripts exposed this as a configurable environment variable. This meant:

- You could not change the VM size without directly editing `main.bicep`
- The value in `main.parameters.json` was never passed to the Bicep deployment (via `azd`)
- `deploy.sh` and `deploy.ps1` never included `vmSize` in the parameters sent to Azure

## Root Cause

Three files were missing support for `vmSize`:

| File | What was missing |
|---|---|
| `infra/main.parameters.json` | No `vmSize` entry → `azd provision` always used the Bicep default |
| `infra/deploy.sh` | No `AZURE_VM_SIZE` variable and no `vmSize` in `PARAMS` array |
| `infra/deploy.ps1` | No `$AzureVmSize` variable, no `vmSize` in parameters hashtable, not shown in deployment summary |

## Changes Made

### 1. `infra/main.parameters.json`

Added the `vmSize` parameter so `azd provision` picks it up from the environment.

**Where to insert:** Inside the root `parameters` object, after the `deployVPN` block (around line 35):

```json
      "deployVPN": {
        "value": "${AZURE_DEPLOY_VPN}"
      },
      "vmSize": {                          ← add this block
        "value": "${AZURE_VM_SIZE}"
      },
```

**Why:** `azd` reads `main.parameters.json` and substitutes `${VAR_NAME}` tokens with the corresponding environment variable values. Without this entry, `azd` never passes `vmSize` to the Bicep deployment, regardless of what environment variable is set.

### 2. `infra/deploy.sh`

Added variable declaration with a safe default and included it in the deployment parameters.

**Where to insert — variable declaration:** In the "Network and VM settings" block (around line 56), after the `AZURE_DEPLOY_VPN` line:

```bash
AZURE_DEPLOY_VPN="${AZURE_DEPLOY_VPN:-false}"
AZURE_VM_SIZE="${AZURE_VM_SIZE:-Standard_D8s_v5}"  ← add this line
VM_USER_PASSWORD="${VM_USER_PASSWORD:-}"
```

**Where to insert — PARAMS array:** Inside the `deploy_bicep()` function (around line 222), after the `deployVPN` entry:

```bash
        "deployVM=$AZURE_DEPLOY_VM"
        "deployVPN=$AZURE_DEPLOY_VPN"
        "vmSize=$AZURE_VM_SIZE"           ← add this line
        "ai_vision_enabled=$AI_VISION_ENABLED"
```

**Why:** `deploy.sh` builds a `PARAMS` array that is passed directly to `az deployment sub create`. Without `vmSize` in this array, the Bicep parameter is never set and the hardcoded default is always used.

### 3. `infra/deploy.ps1`

Added variable reading, parameter in the deployment hashtable, and display in the summary.

**Where to insert — variable declaration:** In the "Network and VM settings" block (around line 62), after the `$AzureDeployVpn` line:

```powershell
$AzureDeployVpn = if ($env:AZURE_DEPLOY_VPN) { $env:AZURE_DEPLOY_VPN } else { "false" }
$AzureVmSize    = if ($env:AZURE_VM_SIZE)    { $env:AZURE_VM_SIZE }    else { "Standard_D8s_v5" }  ← add this line
$VmUserPassword = if ($env:VM_USER_PASSWORD) { $env:VM_USER_PASSWORD } else { "" }
```

**Where to insert — `$parameters` hashtable:** Inside `Start-BicepDeployment`, after the `deployVPN` entry (around line 240):

```powershell
        deployVM  = $script:AzureDeployVm
        deployVPN = $script:AzureDeployVpn
        vmSize    = $script:AzureVmSize      ← add this line
        ai_vision_enabled = $script:AiVisionEnabled
```

**Where to insert — deployment summary:** Inside `Show-DeploymentSummary`, after the `Deploy VPN` line (around line 349):

```powershell
    Write-Info "Deploy VPN:          $($script:AzureDeployVpn)"
    Write-Info "VM Size:             $($script:AzureVmSize)"   ← add this line
    Write-Info "Function App Plan:   $($script:FunctionAppHostPlan)"
```

**Why:** Same root cause as `deploy.sh` — the PowerShell deployment script builds its own parameters object independently. The summary line was also added so operators can confirm the intended VM size before approving the deployment.

---

## How to Change the VM Size

### When does this apply?

Only when deploying with network isolation enabled:

```
AZURE_NETWORK_ISOLATION=true
AZURE_DEPLOY_VM=true
```

If either flag is `false`, no VM is deployed and `AZURE_VM_SIZE` is ignored.

### Step 1: Check quota availability in your target region

Before changing the VM size, verify that your Azure subscription has quota for the desired VM family in the target region.

**Using Azure CLI (Bash/zsh):**
```bash
# Check quota for a specific VM family
az vm list-usage --location eastus2 --output table | grep -i "DSv4"

# Check if a specific VM size is available in the region
az vm list-skus --location eastus2 --size Standard_D8s_v4 --output table
```

Expected output for quota check:
```
Name                               CurrentValue    Limit
---------------------------------  --------------  -------
Standard DDSv4 Family vCPUs        0               0
Standard DSv4 Family vCPUs         8               50      ← 8 used of 50 available ✓
Standard EDSv4 Family vCPUs        0               0
```

Expected output for SKU availability check:
```
ResourceType    Locations    Name               Zones    Restrictions
--------------  -----------  -----------------  -------  --------------
virtualMachines  eastus2     Standard_D8s_v4    1,2,3    None           ← available in all zones ✓
```

> If `Restrictions` shows `NotAvailableForSubscription`, the size is restricted in that region for your subscription. Choose a different size or region.

**Using Azure CLI (PowerShell):**
```powershell
# Check quota for a specific VM family
az vm list-usage --location eastus2 --output table | Select-String "DSv4"

# Check if a specific VM size is available in the region
az vm list-skus --location eastus2 --size Standard_D8s_v4 --output table
```

Expected output is the same as the Bash version above.

**Using Az PowerShell module:**
```powershell
# Requires Az.Compute module
Install-Module -Name Az.Compute -Scope CurrentUser

# Check quota for a VM family
Get-AzVMUsage -Location "eastus2" | Where-Object { $_.Name.Value -like "*DSv4*" }

# Check SKU availability
Get-AzComputeResourceSku -Location "eastus2" | Where-Object { $_.Name -eq "Standard_D8s_v4" }
```

Expected output for `Get-AzVMUsage`:
```
Name                          : StandardDSv4Family
LocalizedName                 : Standard DSv4 Family vCPUs
CurrentValue                  : 8
Limit                         : 50       ← quota available ✓
```

Expected output for `Get-AzComputeResourceSku`:
```
ResourceType : virtualMachines
Name         : Standard_D8s_v4
Locations    : {eastus2}
Restrictions : {}     ← empty means no restrictions ✓
```

**How to interpret the results:**

| Scenario | What you see | Action |
|---|---|---|
| Quota available | `CurrentValue` < `Limit` and `Limit` > 0 | Proceed with deployment |
| No quota | `Limit` = 0 | Request quota increase in Azure Portal |
| At limit | `CurrentValue` == `Limit` | Free up existing VMs or request increase |
| Size restricted | `Restrictions` = `NotAvailableForSubscription` | Choose a different size or region |

To request a quota increase: Azure Portal → **Subscriptions** → your subscription → **Usage + quotas** → find the family → click **Request increase**.

### Step 2: Choose your VM size

Common VM families and their size naming patterns:

| Azure Portal Family Name | VM Size Format | Example |
|---|---|---|
| Standard DSv4 Family vCPUs | `Standard_D{n}s_v4` | `Standard_D8s_v4` |
| Standard DSv5 Family vCPUs | `Standard_D{n}s_v5` | `Standard_D8s_v5` *(default)* |
| Standard DDSv4 Family vCPUs | `Standard_D{n}ds_v4` | `Standard_D8ds_v4` |
| Standard EDSv4 Family vCPUs | `Standard_E{n}ds_v4` | `Standard_E8ds_v4` |

Available vCPU counts per family: `2, 4, 8, 16, 32, 64`

### Step 3: Set the environment variable and deploy

**Using `azd` (recommended):**
```bash
azd env set AZURE_VM_SIZE Standard_D8s_v4
azd provision
```

**Using `deploy.sh` (Linux/macOS):**
```bash
export AZURE_VM_SIZE=Standard_D8s_v4
./infra/deploy.sh
```

**Using `deploy.ps1` (Windows):**
```powershell
$env:AZURE_VM_SIZE = "Standard_D8s_v4"
.\infra\deploy.ps1
```

### Step 4: Confirm the value before deployment

When using `deploy.ps1`, the deployment summary displayed before confirmation will show the VM size:

```
[INFO] ===================================================
[INFO] Deployment Summary
[INFO] ===================================================
[INFO] Environment:         my-env
[INFO] Location:            eastus2
[INFO] Deploy VM:           true
[INFO] Deploy VPN:          false
[INFO] VM Size:             Standard_D8s_v4       ← confirm this
[INFO] Function App Plan:   FlexConsumption
[INFO] ===================================================
Do you want to proceed with the deployment? (yes/no):
```

---

## VM Generations Compatible with MCAP/MngEnv Subscriptions

MCAP and MngEnv subscriptions (e.g. `ME-MngEnvMCAP887462-*`) have **internal quota restrictions** on newer VM generations (v5, v6) that do NOT appear in `az vm list-skus` or `az vm list-usage`. These SKUs may show `None` restrictions and `0/100` family quota, but deployment will still fail with:

```
InternalSubscriptionIsOverQuotaForSku: Current Limit (Standard VMs): 0
```

| Generation | Works on MCAP? | Notes |
|---|---|---|
| DSv3 | ✅ | Available |
| DSv4 | ✅ | **Recommended** |
| DSv5 | ❌ | Internal limit = 0 |
| DSv6 | ❌ | Internal limit = 0 (even though `list-skus` shows None) |

**Use DSv4 for MCAP/sandbox environments:**
```bash
azd env set AZURE_VM_SIZE Standard_D4s_v4   # 4 vCPUs – jumpbox standard
azd env set AZURE_VM_SIZE Standard_D8s_v4   # 8 vCPUs – if more resources needed
```

**To find all sizes without Location restrictions (safe for deployment):**
```bash
az vm list-skus --location eastus2 --size Standard_D \
  --resource-type virtualMachines --output json \
  | jq -r '.[] 
    | select(.restrictions | map(select(.type == "Location")) | length == 0)
    | select(.name | test("Standard_D[0-9]+s_v[3-5]$"))
    | .name' \
  | sort -V
```

> **Note:** This command filters by `type: Location` (full region block), not `type: Zone` (single zone block). Both DSv3 and DSv4 appear in results. Avoid v5/v6 on MCAP subscriptions even if they appear in this list.

## Quick Reference

| Scenario | Command |
|---|---|
| Check DSv4 quota in East US 2 | `az vm list-usage --location eastus2 --output table \| grep -i "DSv4"` |
| Use smaller VM (4 vCPUs, DSv4) | `azd env set AZURE_VM_SIZE Standard_D4s_v4` |
| Use default VM (8 vCPUs, DSv5) | `azd env set AZURE_VM_SIZE Standard_D8s_v5` |
| Use larger VM (16 vCPUs, DSv4) | `azd env set AZURE_VM_SIZE Standard_D16s_v4` |

---

# Fix: Wrong Subnet Delegation for FlexConsumption Function App with Network Isolation

## Background

When `AZURE_NETWORK_ISOLATION=true`, the Function App is integrated into the VNet via the `appServicesSubnet`. Azure requires the subnet to carry the correct delegation based on the Function App hosting plan:

- **Dedicated plan**: requires `Microsoft.Web/serverFarms` delegation
- **FlexConsumption plan**: requires `Microsoft.App/environments` delegation

FlexConsumption Function Apps run on Azure Container Apps infrastructure (internally codenamed "Legion"). Azure attaches a `serviceAssociationLink` named `legionservicelink` to the subnet during deployment. For this SAL to be valid, the subnet **must** have `Microsoft.App/environments` delegation.

## Problem

The deployment fails with:

```
BadRequest: SubnetMissingRequiredDelegation
Subnet .../appServicesSubnet requires any of the following delegation(s)
[Microsoft.App/environments] to reference service association link
.../legionservicelink. Those delegations are either missing or getting
deleted from subnet.
```

This happens on the second (or later) `azd provision` run against the same environment when:
1. The first run deployed a FlexConsumption Function App, creating `legionservicelink` on the subnet
2. The Bicep then tries to update the VNet, re-applying `Microsoft.Web/serverFarms` delegation
3. Azure rejects the update because the existing `legionservicelink` requires `Microsoft.App/environments`

## Root Cause

Two files were missing the conditional delegation logic:

| File | What was missing |
|---|---|
| `infra/modules/network/vnet.bicep` | `appServicesSubnet` always delegated to `Microsoft.Web/serverFarms`, regardless of the Function App plan |
| `infra/main.bicep` | `functionAppHostPlan` was never passed to the `vnet` module |

## Changes Made

### 1. `infra/modules/network/vnet.bicep`

**Where to insert — parameter declaration:** After `param appServicePlanName string` (around line 22):

```bicep
param appServicePlanId string
param appServicePlanName string
param functionAppHostPlan string = 'FlexConsumption'   ← add this line
param tags object = {}
```

**Where to change — `appServicesSubnet` delegation:** In the `subnets` array variable (around line 198), replace the delegation block:

```bicep
// BEFORE (always Web/serverFarms):
delegations: [
  {
    name: appServicePlanName
    properties: {
      serviceName: 'Microsoft.Web/serverFarms'
      ...
    }
  }
]

// AFTER (conditional based on plan):
delegations: [
  {
    name: functionAppHostPlan == 'FlexConsumption' ? 'flexConsumptionDelegation' : appServicePlanName
    properties: {
      serviceName: functionAppHostPlan == 'FlexConsumption' ? 'Microsoft.App/environments' : 'Microsoft.Web/serverFarms'
      actions: [
        'Microsoft.Network/virtualNetworks/subnets/action'
      ]
    }
    type: 'Microsoft.Network/virtualNetworks/subnets/delegations'
  }
]
```

**Why:** The delegation on `appServicesSubnet` must match the runtime model of the Function App. FlexConsumption uses `Microsoft.App/environments` because it runs on Container Apps. Without this, the second `azd provision` will fail because the existing `legionservicelink` becomes invalid.

### 2. `infra/main.bicep`

**Where to change:** In the `vnet` module call (around line 663), add `functionAppHostPlan` to the params:

```bicep
module vnet './modules/network/vnet.bicep' = if (_networkIsolation && !_vnetReuse) {
  name: 'virtual-network'
  params: {
    ...
    appServicePlanId: hostingPlan.outputs.resourceId
    appServicePlanName: hostingPlan.outputs.name
    functionAppHostPlan: functionAppHostPlan   ← add this line
  }
}
```

**Why:** Without passing `functionAppHostPlan` to the module, the conditional in `vnet.bicep` always evaluates against the default value instead of the actual deployment configuration.

---

## How to Re-provision After This Fix

If the subnet already has a stale `legionservicelink` from a previous failed deployment, the VNet must be deleted before re-provisioning so Azure can recreate the subnet with the correct delegation:

```bash
# Delete the VNet (and its subnets — the SAL will be removed)
az network vnet delete \
  --name vnet-ai-<suffix> \
  --resource-group <your-resource-group>

# Re-run provision — the VNet will be recreated with the correct delegation
azd provision
```

> **Why delete the VNet?** The `legionservicelink` SAL is owned by the Container Apps infrastructure and cannot be deleted directly. Deleting the subnet (or the entire VNet) forces Azure to remove it. Once the subnet is recreated with `Microsoft.App/environments` delegation from the start, the SAL will be created correctly on the next provision.

---

## Quick Reference

| Scenario | Delegation needed |
|---|---|
| `FUNCTION_APP_HOST_PLAN=FlexConsumption` (default) | `Microsoft.App/environments` |
| `FUNCTION_APP_HOST_PLAN=Dedicated` | `Microsoft.Web/serverFarms` |

---

# Fix 3: AccountProvisioningStateInvalid — AI Foundry Private Endpoint Race Condition

## Problem

When deploying with `AZURE_NETWORK_ISOLATION=true`, `azd provision` fails with:

```
(✓) Done: Foundry: aif-<suffix> (19.775s)
(x) Failed: Private Endpoint: pep-aif-<suffix>-account-0
    Code: AccountProvisioningStateInvalid
    Message: Call to Microsoft.CognitiveServices/accounts failed.
             Account .../aif-<suffix> in state Accepted
```

## Root Cause

The AVM pattern module `avm/ptn/ai-ml/ai-foundry:0.6.0` creates the CognitiveServices account **and** its Private Endpoint in the same ARM deployment sweep. ARM can run both resources in parallel within the module because there is no strict sequential dependency between them at the ARM-template level. When the PE creation starts, the account's internal `provisioningState` is still `Accepted` (the service is still initializing internally), even though the ARM resource has been created. The PE creation call then fails because it validates the target account's internal state before connecting.

Importantly, this version is the **latest** available in the Bicep public registry (confirmed: 0.1.0 → 0.6.0, no higher version), so an upgrade cannot fix this.

## Why Re-running Works

On a re-run, the account already exists and is in `Succeeded` state, so the PE creation succeeds immediately. This is why `azd provision` idempotency hides the bug on second run.

## Fix

The fix separates PE creation from the AVM module. Instead of letting the AVM module create the PE internally (triggered by `privateEndpointSubnetResourceId`), the PE is created in a dedicated `aiFoundryPe` module **after** the `aiFoundry` module completes, with an explicit `dependsOn: [aiFoundry]`. This guarantees ARM runs them sequentially, giving the account's internal state time to reach `Succeeded` before the PE connection is attempted.

Additionally, `private-endpoint.bicep` was extended to accept a `dnsZoneIds` array because the CognitiveServices `account` group endpoint requires three DNS zone configs in a single PE:

| DNS Zone | Purpose |
|---|---|
| `privatelink.cognitiveservices.azure.com` | CognitiveServices API |
| `privatelink.openai.azure.com` | Azure OpenAI API |
| `privatelink.services.ai.azure.com` | AI Services API |

## Changes Made

### 1. `infra/modules/network/private-endpoint.bicep`

Extended to support multiple DNS zones via a new optional `dnsZoneIds array` parameter. The `dnsZoneId` parameter is now optional with a default of `''`. Existing callers that pass `dnsZoneId:` are unaffected — `effectiveZoneIds` falls back to `[dnsZoneId]`.

### 2. `infra/main.bicep` — `aiFoundry` module params

Removed `networking` from `aiFoundryConfiguration` and set `privateEndpointSubnetResourceId: ''`. This prevents the AVM module from creating the PE internally.

**Before:**
```bicep
aiFoundryConfiguration: {
  accountName: aiFoundryName
  location: aoaiLocation
  disableLocalAuth: false
  networking: _networkIsolation ? {
    cognitiveServicesPrivateDnsZoneResourceId: cogservicesDnsZone.outputs.id
    openAiPrivateDnsZoneResourceId: openaiDnsZone.outputs.id
    aiServicesPrivateDnsZoneResourceId: aiServicesDnsZone.outputs.id
  } : null
}
privateEndpointSubnetResourceId: _networkIsolation ? vnet.outputs.aiSubId : ''
```

**After:**
```bicep
aiFoundryConfiguration: {
  accountName: aiFoundryName
  location: aoaiLocation
  disableLocalAuth: false
  // networking omitted — PE created externally (see aiFoundryPe module below)
}
privateEndpointSubnetResourceId: ''   // PE created externally
```

### 3. `infra/main.bicep` — new `aiFoundryPe` module (added after the `aiFoundry` module)

```bicep
module aiFoundryPe './modules/network/private-endpoint.bicep' = if (_networkIsolation && !_vnetReuse) {
  name: 'aiFoundryPe'
  params: {
    location: location
    name: 'pep-${aiFoundryName}-account'
    tags: tags
    subnetId: vnet.outputs.aiSubId
    serviceId: resourceId('Microsoft.CognitiveServices/accounts', aiFoundryName)
    groupIds: ['account']
    dnsZoneIds: [
      cogservicesDnsZone.outputs.id
      openaiDnsZone.outputs.id
      aiServicesDnsZone.outputs.id
    ]
  }
  dependsOn: [aiFoundry]
}
```

The `dependsOn: [aiFoundry]` ensures ARM does not start this module until the entire `aiFoundry` deployment (account + project workspace) is complete and in `Succeeded` state.
