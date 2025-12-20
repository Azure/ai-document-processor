# Enhanced Tracing Configuration (This Project)

This project has enhanced tracing enabled in `pipeline/host.json` for better observability:

```json
{
  "extensions": {
    "durableTask": {
      "tracing": {
        "traceInputsAndOutputs": true,
        "traceReplayEvents": true,
        "distributedTracingEnabled": true,
        "version": "V2"
      }
    }
  },
  "logging": {
    "logLevel": {
      "Host.Triggers.DurableTask": "Information"
    }
  }
}
```

### What Each Setting Does

| Setting                       | Value           | What It Enables                                                               |
| ----------------------------- | --------------- | ----------------------------------------------------------------------------- |
| `traceInputsAndOutputs`     | `true`        | Logs actual data passed to/from activities (prompts, payloads, blob URIs)     |
| `traceReplayEvents`         | `true`        | Logs orchestrator replay events showing retry attempts and re-execution flow  |
| `distributedTracingEnabled` | `true`        | Correlates ALL traces with a single `operation_Id` for end-to-end debugging |
| `version`                   | `V2`          | Uses newer tracing format with better App Insights integration                |
| `Host.Triggers.DurableTask` | `Information` | More detailed trigger-level logging                                           |

### Using Enhanced Tracing in App Insights

With these settings enabled, you can trace a single document through the entire pipeline using the correlated `operation_Id`.

#### Query 1: Find an Orchestration's operation_Id

```kusto
// Find the operation_Id for a specific document
traces 
| where timestamp > ago(1h)
| where message contains "YourDocument.pdf"
| project timestamp, operation_Id, message
| take 1
```

#### Query 2: End-to-End Document Flow

```kusto
// Trace complete flow using operation_Id
let opId = "<paste-operation-id-here>";

union requests, dependencies, traces
| where operation_Id == opId
| project 
    timestamp,
    itemType,
    name = coalesce(name, "trace"),
    message = substring(message, 0, 150)
| order by timestamp asc
```

#### Query 3: See Retry Attempts and Activity Scheduling

```kusto
// View retry events and activity re-scheduling
traces 
| where timestamp > ago(1h)
| where message contains "scheduled" or message contains "Retry" or message contains "failed"
| project timestamp, message
| order by timestamp desc
| take 50
```

#### Query 4: View Activity Inputs/Outputs

```kusto
// See actual data passed to activities (enabled by traceInputsAndOutputs)
traces 
| where timestamp > ago(1h)
| where message contains "Input:" or message contains "Output:"
| project timestamp, message
| order by timestamp desc
```

### Sample End-to-End Trace Output

With enhanced tracing, you'll see the complete flow in App Insights:

```
Timestamp   | Type       | Name                        | Message
------------|------------|-----------------------------|-----------------------------------------
22:17:31    | dependency | create_orchestration        | 
22:17:32    | request    | orchestration:process_blob  | 
22:17:32    | trace      |                             | Function 'process_blob (Orchestrator)' started
22:17:36    | trace      |                             | Processing document file: bronze/MyDoc.pdf
22:17:36    | trace      |                             | 'runDocIntel (Activity)' scheduled
22:17:52    | request    | activity:runDocIntel        | 
22:17:58    | trace      |                             | runDocIntel completed
22:17:59    | trace      |                             | 'callAoai (Activity)' scheduled
22:19:18    | request    | activity:callAoai           | 
22:19:45    | trace      |                             | callAoai completed
22:19:46    | trace      |                             | 'writeToBlob (Activity)' scheduled
22:25:09    | request    | activity:writeToBlob        | 
22:25:10    | trace      |                             | Orchestration completed
```

### Combining with Durable Functions Monitor

The Durable Functions Monitor VS Code extension shows orchestration-level details:

- Instance ID, status, timestamps
- Execution history (which activities ran)
- Inputs and outputs per activity

**App Insights with enhanced tracing adds:**

- Correlated `operation_Id` across ALL activities
- Actual data payloads (prompts, responses)
- Retry events and failure details
- Performance timing across the entire flow
- Integration with Azure Monitor dashboards and alerts

### Troubleshooting with Tracing

| Symptom                    | KQL Query                                                                       |
| -------------------------- | ------------------------------------------------------------------------------- |
| Find 429 rate limit errors | `traces \| where message contains "429"`                                       |
| See retry attempts         | `traces \| where message contains "Retry attempt"`                             |
| Find failed activities     | `requests \| where success == false \| where name contains "activity"`          |
| Check activity duration    | `requests \| where name contains "activity" \| summarize avg(duration) by name` |

---

## Quick Start for This Project

```powershell
# 1. Get environment values
cd c:\MyCode\ADPBase\ADPG-Durable\ai-document-processor
azd env get-values | Select-String "STORAGE_ACCOUNT"

# 2. The function storage account is: stvkulfxjlgwhiqfunc
# 3. Connect Durable Functions Monitor to this storage account
# 4. Task Hub name = Function App name (if not customized in host.json)
```




# Durable Functions Monitor - VS Code Setup Guide

## Overview

The **Durable Functions Monitor** is a VS Code extension that provides a UI to monitor, debug, and manage Durable Functions orchestrations. It shows orchestration history, status, inputs/outputs, and allows you to purge, rewind, or terminate instances.

## Prerequisites

1. **VS Code Extension**: Install "Durable Functions Monitor" from the VS Code marketplace

   - Extension ID: `DurableFunctionsMonitor.durablefunctionsmonitor`
2. **Azure Storage Account**: Your Durable Functions app must be using Azure Storage (not Netherite or MSSQL backend)
3. **Azure CLI**: Logged in with `az login`

## Connection Methods

### Method 1: Connect to Deployed Azure Function (Recommended)

1. Open the Durable Functions Monitor panel in VS Code (click the icon in the Activity Bar)
2. Click **"Connect to Task Hub..."**
3. Select your **Azure Subscription**
4. Select your **Storage Account** (e.g., `stvkulfxjlgwhiqfunc`)
5. Select the **Task Hub** name

> **Note**: The Task Hub name defaults to your Function App name unless overridden in `host.json` under `extensions.durableTask.hubName`.

### Method 2: Connect via Connection String

1. Get your storage connection string:

   ```powershell
   az storage account show-connection-string `
     --name <storage-account-name> `
     --resource-group <resource-group> `
     --query connectionString -o tsv
   ```
2. In Durable Functions Monitor, select **"Connect to Task Hub..."**
3. Choose **"Enter connection string manually"**
4. Paste the connection string
5. Select or enter the Task Hub name

### Method 3: Connect to Local Azurite (Local Development)

1. Ensure Azurite is running (storage emulator)
2. Use the default connection string:
   ```
   UseDevelopmentStorage=true
   ```
3. The Task Hub name will be based on your local function app name

## Finding Your Task Hub Name

The Task Hub name is configured in `host.json`:

```json
{
  "extensions": {
    "durableTask": {
      "hubName": "MyCustomTaskHub"
    }
  }
}
```

If not specified, it defaults to the **Function App name**.

For this project (ADP-Durable), check:

- [host.json](../ADPG-Durable/ai-document-processor/pipeline/host.json)

## Troubleshooting

### "No orchestrations found"

- Ensure you've triggered at least one orchestration
- Check you're connected to the correct Task Hub
- Verify the storage account is the one your Function App uses

### "Select a default function" prompt

- This appears when you first load the monitor
- Simply select your Function App or Task Hub from the dropdown

### Connection Issues

- Verify your Azure CLI login: `az login`
- Check you have **Storage Blob Data Reader** role on the storage account
- For local development, ensure Azurite is running

### Can't see recent orchestrations

- Click the **Refresh** button in the monitor
- Check the time filter (default may hide old orchestrations)

## Useful Features

| Feature                 | Description                                     |
| ----------------------- | ----------------------------------------------- |
| **Instance View** | See detailed execution history, inputs, outputs |
| **Purge**         | Delete orchestration history                    |
| **Rewind**        | Replay failed orchestration from a checkpoint   |
| **Terminate**     | Stop a running orchestration                    |
| **Filter**        | Search by instance ID, status, or time range    |

---

## References

- [Durable Functions Monitor - GitHub](https://github.com/microsoft/DurableFunctionsMonitor)
- [Durable Functions Monitor - VS Code Marketplace](https://marketplace.visualstudio.com/items?itemName=DurableFunctionsMonitor.durablefunctionsmonitor)
- [Durable Functions Documentation](https://learn.microsoft.com/en-us/azure/azure-functions/durable/durable-functions-overview)
