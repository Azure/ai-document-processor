# Pull Request: Fix VM Size, Subnet Delegation & AI Foundry PE Race Condition

**Branch:** `local-documentation` → `main`
**Repo:** `Azure/ai-document-processor`

---

## Summary

This PR fixes three independent infrastructure bugs that prevent successful deployment when `AZURE_NETWORK_ISOLATION=true`:

1. **`AZURE_VM_SIZE` environment variable had no effect** — the VM size was hardcoded in Bicep and never read from env vars or `main.parameters.json`.
2. **Wrong subnet delegation for FlexConsumption Function Apps** — `appServicesSubnet` was always delegated to `Microsoft.Web/serverFarms`, but FlexConsumption requires `Microsoft.App/environments`. This caused deployment failures on re-provision with error `SubnetMissingRequiredDelegation`.
3. **AI Foundry Private Endpoint race condition** — `AccountProvisioningStateInvalid` on first provision because the PE was created in parallel with the account inside the AVM module before the account's internal state reached `Succeeded`.

---

## Files Changed

| File | Change |
|---|---|
| `infra/main.parameters.json` | Added `vmSize` parameter mapping to `${AZURE_VM_SIZE}` |
| `infra/deploy.sh` | Added `AZURE_VM_SIZE` variable + pass to deployment params |
| `infra/deploy.ps1` | Added `$AzureVmSize` variable + pass to deployment params + show in summary |
| `infra/main.bicep` | Pass `functionAppHostPlan` to `vnet` module; remove PE from `aiFoundry` AVM call; add external `aiFoundryPe` module |
| `infra/modules/network/vnet.bicep` | Add `functionAppHostPlan` param + conditional subnet delegation |
| `infra/modules/network/private-endpoint.bicep` | Add optional `dnsZoneIds array` param for multi-zone PE support |

---

## Bug 1: `AZURE_VM_SIZE` Not Configurable

### Problem

`infra/main.bicep` defines:
```bicep
param vmSize string = 'Standard_D8s_v5'
```

But this value was never exposed via environment variables. `main.parameters.json` had no `vmSize` entry, and neither `deploy.sh` nor `deploy.ps1` passed it to the deployment. Setting `AZURE_VM_SIZE` in the environment had no effect.

### Fix

**`infra/main.parameters.json`** — added parameter mapping:
```json
"vmSize": {
  "value": "${AZURE_VM_SIZE}"
}
```

**`infra/deploy.sh`** — added variable and PARAMS entry:
```bash
AZURE_VM_SIZE="${AZURE_VM_SIZE:-Standard_D8s_v5}"
# ...
"vmSize=$AZURE_VM_SIZE"
```

**`infra/deploy.ps1`** — added variable, hashtable entry, and summary line:
```powershell
$AzureVmSize = if ($env:AZURE_VM_SIZE) { $env:AZURE_VM_SIZE } else { "Standard_D8s_v5" }
# ...
vmSize = $script:AzureVmSize
# ...
Write-Info "VM Size: $($script:AzureVmSize)"
```

### How to use

```bash
# azd
azd env set AZURE_VM_SIZE Standard_D4s_v4
azd provision

# deploy.sh
export AZURE_VM_SIZE=Standard_D4s_v4
./infra/deploy.sh
```

> Note: VM is only deployed when both `AZURE_DEPLOY_VM=true` AND `AZURE_NETWORK_ISOLATION=true`.

---

## Bug 2: Wrong Subnet Delegation for FlexConsumption + Network Isolation

### Problem

When `AZURE_NETWORK_ISOLATION=true`, the Function App is VNet-integrated via `appServicesSubnet`. The delegation on this subnet must match the Function App hosting plan:

- **Dedicated** → `Microsoft.Web/serverFarms`
- **FlexConsumption** → `Microsoft.App/environments`

FlexConsumption runs on Azure Container Apps infrastructure. During deployment, Azure attaches a `serviceAssociationLink` named `legionservicelink` to the integrated subnet. This SAL requires `Microsoft.App/environments` delegation.

The Bicep always deployed `appServicesSubnet` with `Microsoft.Web/serverFarms` delegation. On a re-provision, Azure would attempt to change the delegation back to `Microsoft.Web/serverFarms`, but the existing `legionservicelink` requires `Microsoft.App/environments` — causing the deployment to fail with:

```
SubnetMissingRequiredDelegation: Subnet .../appServicesSubnet requires
any of the following delegation(s) [Microsoft.App/environments] to
reference service association link .../legionservicelink.
```

Additionally, `functionAppHostPlan` was never passed to the `vnet` module, so the subnet delegation could not be made conditional.

### Diff

**`infra/modules/network/vnet.bicep`:**
```diff
 param appServicePlanId string
 param appServicePlanName string
+param functionAppHostPlan string = 'FlexConsumption'
 param tags object = {}

 // appServicesSubnet delegation:
-  name : appServicePlanName
+  name: functionAppHostPlan == 'FlexConsumption' ? 'flexConsumptionDelegation' : appServicePlanName
   properties: {
-    serviceName: 'Microsoft.Web/serverFarms'
+    serviceName: functionAppHostPlan == 'FlexConsumption' ? 'Microsoft.App/environments' : 'Microsoft.Web/serverFarms'
```

**`infra/main.bicep`:**
```diff
     appServicePlanId: hostingPlan.outputs.resourceId
     appServicePlanName: hostingPlan.outputs.name
+    functionAppHostPlan: functionAppHostPlan
```

### How to recover an existing environment

If the subnet already has a stale `legionservicelink` from a previous failed deployment, the VNet must be deleted before re-provisioning:

```bash
az network vnet delete \
  --name vnet-ai-<suffix> \
  --resource-group <your-resource-group>

azd provision
```

---

## Testing

Verified against environment with:
- `AZURE_NETWORK_ISOLATION=true`
- `AZURE_DEPLOY_VM=true`
- `FUNCTION_APP_HOST_PLAN=FlexConsumption` (default)
- `AZURE_LOCATION=eastus2`

### Checklist

- [ ] `azd provision` completes without `SubnetMissingRequiredDelegation` error on first provision
- [ ] `azd provision` completes without `AccountProvisioningStateInvalid` error on first provision
- [ ] `azd provision` completes without error on re-provision (idempotent)
- [ ] Setting `AZURE_VM_SIZE` correctly sizes the jumpbox VM
- [ ] Setting `FUNCTION_APP_HOST_PLAN=Dedicated` still uses `Microsoft.Web/serverFarms` delegation
- [ ] AI Foundry private endpoint (`pep-*-account`) connects successfully to the CognitiveServices account

---

---

## Bug 3: AI Foundry Private Endpoint Race Condition (`AccountProvisioningStateInvalid`)

### Problem

On **first provision** with `AZURE_NETWORK_ISOLATION=true`, the deployment fails with:

```
(✓) Done: Foundry: aif-<suffix> (19.775s)
(x) Failed: Private Endpoint: pep-aif-<suffix>-account-0
    Code: AccountProvisioningStateInvalid
    Message: Account .../aif-<suffix> in state Accepted
```

The AVM module `avm/ptn/ai-ml/ai-foundry:0.6.0` creates the CognitiveServices account and its Private Endpoint in the **same ARM deployment**, allowing them to run in parallel. ARM sees the account resource as created, but the account's internal `provisioningState` is still `Accepted` (service initialization in progress). The PE creation call validates the account state before connecting and fails.

Version `0.6.0` is the latest in the registry — an upgrade cannot fix this.

### Fix

**`infra/main.bicep` — `aiFoundry` module:** Removed `networking` from `aiFoundryConfiguration` and set `privateEndpointSubnetResourceId: ''` to disable internal PE creation.

**`infra/modules/network/private-endpoint.bicep`:** Added optional `dnsZoneIds array` parameter so a single PE can register all three DNS zones required for CognitiveServices (`privatelink.cognitiveservices.azure.com`, `privatelink.openai.azure.com`, `privatelink.services.ai.azure.com`).

**`infra/main.bicep` — new `aiFoundryPe` module** (added after `aiFoundry`):
```bicep
module aiFoundryPe './modules/network/private-endpoint.bicep' = if (_networkIsolation && !_vnetReuse) {
  name: 'aiFoundryPe'
  params: {
    name: 'pep-${aiFoundryName}-account'
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

The `dependsOn: [aiFoundry]` forces ARM to complete the entire AI Foundry deployment (account + project workspace) before creating the PE, by which point the account is in `Succeeded` state.

---

## Related Issues

- `SubnetMissingRequiredDelegation` on Function App `legionservicelink` during `azd provision`
- `AZURE_VM_SIZE` environment variable ignored by `azd provision` and deployment scripts
- `AccountProvisioningStateInvalid` on first `azd provision` with `AZURE_NETWORK_ISOLATION=true`
