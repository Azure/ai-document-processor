## Bucket 1: OpenAI Model Version Fix (Minor)

| File                 | Change                                                   | Reason                                                |
| -------------------- | -------------------------------------------------------- | ----------------------------------------------------- |
| `infra/main.bicep` | `gpt-5-mini` version: `2025-09-07` → `2025-08-07` | Model version 2025-09-07 not available in all regions |

---

## Bucket 2: Enable EventGrid Blob Trigger for Flex Consumption (Major)

Flex Consumption plan **does not support polling-based blob triggers** - only EventGrid-based triggers work.

EventGrid is the newest, fastest, cheapest pub-sub messaging solution and it works great for realtime triggers in applications.

EventGrid-based triggers also provide lower latency than the polling mechanism. This required four interconnected fixes across infrastructure, code, and deployment scripts.

**Key concepts:**

- EventGrid uses "system topics" as core part of eventgrids. Azure sends event to EventGrid System Topic (publisher) which sends event to Function (subscriber).
- You need a system topic to publish events to the event grid. It is the source
- You need event subscriptions to route the event to the right function
- The flow is Storage Account gets blob --> System Topic generates event --> Event Subscription routes event to appropriate webhook --> Function triggered to process blob
- In this code all it does is trigger the function when the blob lands. No eventgrid rework required for processing other content or changing function activities

### **To change from polling triggers to EventGrid triggers, I did the following:**

#### ***INFRA (azd provision)***

1. **Pre-create the EventGrid System Topic `bronzeEventGridTopic`** in `infra/main.bicep`

   1. Pre-creating in Bicep ensures the system topic exists before the postDeploy script tries to create the subscription (how it is done in the official quickstart: [Azure-Samples/functions-quickstart-python-azd-eventgrid-blob: This template repository contains a Blob trigger with the Event Grid source type reference sample for Azure Functions written in Python and deployed to Azure using the Azure Developer CLI (azd).](https://github.com/Azure-Samples/functions-quickstart-python-azd-eventgrid-blob))
2. **Explicitly assign the value for** `keyVaultAccessIdentityResourceId` in the Function App in `infra/main.bicep`

   1. `keyVaultAccessIdentityResourceId: uaiFrontendMsi.outputs.id`
   2. This makes it so the function can authenticate and get secrets from Key Vault. QUESTION, why was this not needed for dedicated? Both use UAI
   3. Copilot Claims that dedicated plan explicitly includes clientid in the app setting; i.e., *Dedicated works because each app setting includes `__clientId` suffix (e.g., `AzureWebJobsStorage__clientId`)*. It says FlexCapacity needs `keyVaultAccessIdentityResourceId` for **platform-level** operations (deployment storage, Key Vault references) that don't use app settings. I don't understand it.
   4. **Not included** in Azure official quickstart but it also doesn't use KeyVault
3. **Add Bicep outputs** for `BRONZE_SYSTEM_TOPIC_NAME` and `BRONZE_CONTAINER_NAME` - needed by the postDeploy scripts to create the subscription via CLI. Names have unique suffixes so they can't be hard coded when the event subscription is created. (VIRTUALLY same pattern used in Azure official quickstart: Microsoft's quickstart uses the enum `func.BlobSource.EVENT_GRID` instead of the string `"EventGrid"`. Both are functionally equivalent - the string form was used here for simplicity.)

   #### ***CODE (azd deploy)***
4. **Add Added `source="EventGrid"` to `@app.blob_trigger`** blob trigger decorator in `pipeline/function_app.py` - tells the function app to use EventGrid not polling for blob trigger. (Same pattern used in Azure official quickstart)

   #### ***POST DEPLOYMENT HOOK (runs after deploy)***
5. **Create the EventGrid subscription in `postdeploy`** (not `postprovision`) - the subscription requires the `blobs_extension` webhook key, which only exists after the function code is deployed. (Same pattern used in Azure official quickstart)

   ### Script Changes

   | File                          | Change                                                         | Why                                                                                                                                                                                                                               |
   | ----------------------------- | -------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
   | `azure.yaml`                | Added `interactive`, `continueOnError` to postdeploy hooks | Real-time output visibility; fail-fast if subscription fails<br />interactive: true --> gives more visibility into postDeploy script<br />continueOnError: false --> ensures deployment fails if event subscription isn't created |
   | `scripts/postDeploy.ps1`    | Complete rewrite                                               | Creates EventGrid subscription via CLI, then uploads test blob                                                                                                                                                                    |
   | `scripts/postDeploy.sh`     | Complete rewrite                                               | Same as PowerShell version for Linux/Mac                                                                                                                                                                                          |
   | `scripts/postprovision.ps1` | Moved test blob upload to postDeploy                           | Test blob must upload AFTER EventGrid subscription is created                                                                                                                                                                     |


   > **Note on warmup requests:** The postDeploy scripts include warmup HTTP requests before creating the EventGrid subscription. Microsoft's quickstart does not include warmup, but it's retained here as a defensive measure against cold start timeouts during webhook validation on Flex Consumption.
   >



### Why postdeploy Timing Matters

```
postprovision (after azd provision):
  ❌ Function code not deployed yet
  ❌ blobs_extension key doesn't exist

postdeploy (after azd deploy):
  ✅ Function code is deployed
  ✅ blobs_extension key exists (webhook auth key generated by blob trigger)
  ✅ EventGrid subscription can be created
```

---

## References

This PR follows the pattern established in Microsoft's official EventGrid blob trigger quickstart:

- [Azure Functions EventGrid Blob Trigger Quickstart](https://github.com/Azure-Samples/functions-quickstart-python-azd-eventgrid-blob) - Source of the `postdeploy` hook pattern, System Topic creation in Bicep, and CLI-based subscription creation
- [Flex Consumption Plan - Considerations](https://learn.microsoft.com/en-us/azure/azure-functions/flex-consumption-plan#considerations) - States: *"the Blob storage trigger only supports the Event Grid source"*
- [Blob Trigger Source Parameter](https://learn.microsoft.com/en-us/azure/azure-functions/functions-bindings-storage-blob-trigger?tabs=python-v2#configuration) - Documents the `source` parameter options (`EventGrid` vs `LogsAndContainerScan`)
- [User-Assigned Identity for Key Vault References](https://learn.microsoft.com/en-us/azure/azure-functions/functions-identity-based-connections-tutorial) - Explains why `keyVaultAccessIdentityResourceId` is required: *"Whenever you want to use a user-assigned identity, you must specify it with an ID... Many features that use managed identity assume they should use the system-assigned one by default."*
