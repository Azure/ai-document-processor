# AI Document Processor (ADP) - Official Deployment Guide

> **Last Updated:** December 2024  
> **Status:** Current and Official  
> **Note:** This document supersedes previous troubleshooting guides and reflects the latest working implementation.

---

## Table of Contents

1. [Overview](#overview)
2. [Architecture](#architecture)
3. [Key Components](#key-components)
4. [Deployment Options](#deployment-options)
5. [Quick Start Deployment](#quick-start-deployment)
6. [Infrastructure Details](#infrastructure-details)
7. [Pipeline Activities](#pipeline-activities)
8. [Configuration System](#configuration-system)
9. [Event Grid Integration](#event-grid-integration)
10. [Multi-Modal & Audio Support](#multi-modal--audio-support)
11. [Local Development](#local-development)
12. [Troubleshooting](#troubleshooting)
13. [Recent Changes & Improvements](#recent-changes--improvements)

---

## Overview

The AI Document Processor (ADP) is an Azure-based accelerator that automates document and file processing using Large Language Models (LLMs). The solution uses **Azure Durable Functions** with the function chaining pattern to orchestrate a multi-step pipeline that:

1. Ingests documents (PDF, Word, audio, images) from blob storage
2. Extracts content using Azure Document Intelligence or Speech-to-Text
3. Processes content with Azure OpenAI (via AI Foundry)
4. Writes structured output (JSON) to blob storage

### Business Value

- **Developer Foundation** - Scaffolding for custom document processing workflows
- **Automated Infrastructure** - Bicep templates provision all Azure resources
- **RBAC Configuration** - Managed identities with proper role assignments out-of-the-box
- **Dual Hosting Options** - Dedicated App Service or Flex Consumption plans

---

## Architecture

### Azure Resources Provisioned

| Resource | Purpose |
|----------|---------|
| **Azure Function App** | Hosts the Durable Functions processing pipeline |
| **Azure AI Foundry** | Provides Azure OpenAI model deployment (gpt-5-mini) |
| **Azure AI Services** | Document Intelligence and Speech-to-Text capabilities |
| **Azure Storage Account (Data)** | Bronze/Silver/Gold containers for document lifecycle |
| **Azure Storage Account (Func)** | Function App deployment and runtime storage |
| **Azure App Configuration** | Centralized configuration management |
| **Azure Key Vault** | Secrets management |
| **Azure Cosmos DB** | Conversation history and prompt storage |
| **Application Insights** | Monitoring and logging |
| **Event Grid System Topic** | Blob trigger events for document processing |

### Network Isolation (Optional)

When `networkIsolation=true`:
- All resources deploy with Private Endpoints
- Virtual Network with subnets for AI, App Services, Database
- Private DNS Zones for all services
- Optional VPN Gateway and Bastion Host for access

---

## Key Components

### Function App Structure (`pipeline/`)

```
pipeline/
├── function_app.py          # Main function app with triggers and orchestrators
├── configuration/
│   └── configuration.py     # Azure App Configuration integration
├── activities/
│   ├── callAiFoundry.py     # Standard AOAI text processing
│   ├── callFoundryMultiModal.py  # Multi-modal PDF/image processing
│   ├── runDocIntel.py       # Document Intelligence OCR
│   ├── speechToText.py      # Audio transcription
│   ├── writeToBlob.py       # Output to blob storage
│   └── getBlobContent.py    # Blob content retrieval
└── pipelineUtils/
    ├── azure_openai.py      # OpenAI client utilities
    ├── blob_functions.py    # Blob storage operations
    ├── db.py                # Cosmos DB operations
    └── prompts.py           # Prompt loading utilities
```

### Trigger Types

1. **Blob Trigger with EventGrid** (`start_orchestrator_on_blob`)
   - Triggers on new blobs in the `bronze` container
   - Uses EventGrid source for reliable, scalable triggers
   
2. **HTTP Trigger** (`start_orchestrator_http`)
   - Manual invocation via HTTP POST
   - Useful for testing and external integrations

---

## Deployment Options

### Hosting Plan Selection

| Parameter | `Dedicated` | `FlexConsumption` |
|-----------|-------------|-------------------|
| **VM Type** | Dedicated App Service Plan | Serverless |
| **Scaling** | Manual or Auto-scale rules | Automatic 0-100 instances |
| **Cold Starts** | None (Always On) | Possible |
| **SSH Access** | Available | Not available |
| **Debugging** | Easier | More difficult |
| **SKU Options** | B1, B2, S1, S2, S3, P1v2, P2v2, P3v2 | FC1 |

### Network Isolation

| Parameter | `false` | `true` |
|-----------|---------|--------|
| **Endpoints** | Public | Private only |
| **Security** | Auth-protected | VNet + Auth |
| **Complexity** | Simple | More complex |
| **VM Required** | No | Recommended |

---

## Quick Start Deployment

### Prerequisites

- Azure CLI (`az`)
- Azure Developer CLI (`azd`)
- Python 3.11+
- Azure Functions Core Tools

### Deployment Steps

```bash
# 1. Login to Azure
az login
azd auth login

# 2. (Optional) Pre-configure environment variables to avoid interactive prompts
azd env set AZURE_NETWORK_ISOLATION true
azd env set AZURE_DEPLOY_VM true
azd env set AZURE_VM_SIZE "Standard_D8s_v5"
azd env set AZURE_VM_ANTIMALWARE false          # Disable for isolated VNets without internet
azd env set FUNCTION_APP_HOST_PLAN FlexConsumption
azd env set AOAI_LOCATION "eastus2"             # Defaults to deployment region if not set

# 3. Deploy infrastructure and code
azd up

# 4. When prompted (if not pre-configured), provide:
#    - Environment name
#    - Azure region
#    - User Principal ID: az ad signed-in-user show --query id -o tsv
#    - Network isolation: true or false
#    - VM deployment (if network isolated): true or false
```

### Environment Variables Reference

All parameters can be set via `azd env set <VAR> <VALUE>` before running `azd up` or `azd provision` to avoid interactive prompts.

| Variable | Default | Description |
|----------|---------|-------------|
| `AZURE_LOCATION` | *(prompted)* | Azure region for all resources (e.g., `eastus2`) |
| `AOAI_LOCATION` | Same as `AZURE_LOCATION` | AI Foundry/OpenAI region. Defaults to deployment region. Accepts short names (`eastus2`) or display names (`East US 2`) |
| `AZURE_NETWORK_ISOLATION` | `false` | Enable VNet isolation with private endpoints |
| `AZURE_DEPLOY_VM` | `false` | Deploy a Windows VM for accessing network-isolated resources via Bastion |
| `AZURE_DEPLOY_VPN` | `false` | Deploy a VPN Gateway for on-premises connectivity |
| `AZURE_VM_SIZE` | `Standard_D8s_v5` | VM SKU for the test VM (e.g., `Standard_D4s_v5`, `Standard_D2s_v3`) |
| `AZURE_VM_ANTIMALWARE` | `true` | Install Microsoft AntiMalware extension on the VM. **Set to `false`** in network-isolated VNets without outbound internet access to prevent deployment failures |
| `FUNCTION_APP_HOST_PLAN` | `FlexConsumption` | `FlexConsumption` (serverless, uses Container Apps quota) or `Dedicated` (uses App Service Plan VM quota) |
| `AZURE_VM_SIZE` | `Standard_D8s_v5` | VM size for the test VM |

### Post-Deployment

The `azd up` command runs hooks automatically:
1. **postprovision** - Initial resource configuration
2. **postdeploy** - Creates EventGrid subscription for blob triggers

---

## Infrastructure Details

### AI Foundry Integration

The solution uses the **Azure Verified Module (AVM)** for AI Foundry:

```bicep
module aiFoundry 'br/public:avm/ptn/ai-ml/ai-foundry:0.6.0' = {
  params: {
    baseName: aiFoundryBaseName  // max 12 chars
    includeAssociatedResources: false  // We manage our own resources
    aiFoundryConfiguration: {
      accountName: aiFoundryName
      location: aoaiLocation
      disableLocalAuth: false  // Enable for local development
    }
    aiModelDeployments: [
      {
        name: 'gpt-5-mini'
        model: { format: 'OpenAI', name: 'gpt-5-mini', version: '2025-08-07' }
        sku: { name: 'GlobalStandard', capacity: 100 }
      }
    ]
  }
}
```

### Function App Configuration

The Function App uses **User-Assigned Managed Identity** for all Azure service authentication:

```bicep
var commonAppSettings = {
  AZURE_TENANT_ID: subscription().tenantId
  AZURE_CLIENT_ID: uaiFrontendMsi.outputs.clientId
  APP_CONFIGURATION_URI: 'https://${appConfigName}.azconfig.io'
  AzureWebJobsStorage__credential: 'managedidentity'
  AzureWebJobsStorage__clientId: uaiFrontendMsi.outputs.clientId
  DataStorage__credential: 'managedidentity'
  DataStorage__clientId: uaiFrontendMsi.outputs.clientId
}
```

### Storage Accounts

Two storage accounts are provisioned:

1. **Data Storage** (`st{suffix}data`)
   - `bronze` - Input documents
   - `silver` - Processed output
   - `gold` - Final/enriched data
   - `prompts` - Prompt templates

2. **Function Storage** (`st{suffix}func`)
   - `app-package` - Deployed function code
   - Function runtime tables and queues

---

## Pipeline Activities

### Document Processing Flow

```
Bronze Container (Input)
         │
         ▼
┌─────────────────────────────────────┐
│   File Type Detection               │
│   (PDF, DOCX, PNG, MP3, WAV, etc.) │
└─────────────────────────────────────┘
         │
         ├─── Document ───▶ runDocIntel.py (OCR)
         │                       │
         ├─── Audio ──────▶ speechToText.py (Transcription)
         │                       │
         └─── Multi-Modal ─▶ callFoundryMultiModal.py (Vision API)
                                 │
                                 ▼
                    ┌─────────────────────┐
                    │  callAiFoundry.py   │
                    │  (LLM Processing)   │
                    └─────────────────────┘
                                 │
                                 ▼
                    ┌─────────────────────┐
                    │   writeToBlob.py    │
                    │  (Silver Container) │
                    └─────────────────────┘
```

### Supported File Types

| Category | Extensions |
|----------|------------|
| **Documents** | PDF, DOCX, DOC, XLSX, PPTX, JPG, JPEG, PNG, TIFF, BMP |
| **Audio** | WAV, MP3, OPUS, OGG, FLAC, WMA, AAC, WEBM |

---

## Configuration System

### Azure App Configuration

All runtime configuration is centralized in Azure App Configuration:

```python
from configuration import Configuration

config = Configuration()

# Retrieve values (with Key Vault secret resolution)
openai_endpoint = config.get_value("OPENAI_API_BASE")
openai_model = config.get_value("OPENAI_MODEL")
```

### Configuration Priority

1. Environment variables (when `allow_environment_variables=true`)
2. Azure App Configuration values
3. Key Vault secrets (automatically resolved)

### Key Configuration Values

| Key | Description |
|-----|-------------|
| `OPENAI_API_BASE` | AI Foundry/OpenAI endpoint URL |
| `OPENAI_MODEL` | Model name (e.g., gpt-5-mini) |
| `OPENAI_API_VERSION` | API version (e.g., 2024-05-01-preview) |
| `DATA_STORAGE_ENDPOINT` | Blob storage endpoint |
| `DATA_STORAGE_ACCOUNT_NAME` | Data storage account name |
| `AI_SERVICES_ENDPOINT` | Document Intelligence / Speech endpoint |
| `COSMOS_DB_URI` | Cosmos DB endpoint URL |
| `COSMOS_DB_DATABASE_NAME` | Cosmos DB database name |
| `COSMOS_DB_CONVERSATION_HISTORY_CONTAINER` | Container for conversation history |
| `FINAL_OUTPUT_CONTAINER` | Output container name (default: silver) |
| `PROMPT_FILE` | Prompt configuration filename (prompts.yaml) |
| `AOAI_MULTI_MODAL` | Enable multi-modal processing (true/false) |

---

## Event Grid Integration

### Architecture

The solution uses a **System Topic** pattern for EventGrid, which is more reliable than direct storage event subscriptions:

1. **Bicep creates** the System Topic on the storage account
2. **postDeploy script** creates the Event Subscription after function deployment
3. **Webhook endpoint** uses the `blobs_extension` system key

### Why System Topic Pattern?

- Pre-created topic ensures reliable event routing
- Better webhook validation timeout handling
- Follows Microsoft's official quickstart pattern

### Event Subscription Details

```
Endpoint: https://{functionAppName}.azurewebsites.net/runtime/webhooks/blobs
  ?functionName=Host.Functions.start_orchestrator_on_blob
  &code={blobs_extension_key}

Filter: /blobServices/default/containers/bronze/
Events: Microsoft.Storage.BlobCreated
```

---

## Multi-Modal & Audio Support

### Multi-Modal Processing

Enable multi-modal processing (PDF images + vision API):

```yaml
# Set in Azure App Configuration or environment
AOAI_MULTI_MODAL: "true"
```

When enabled, PDFs are converted to images page-by-page and sent to the vision-capable model.

### Audio Processing

Audio files are automatically detected and processed via Azure AI Services Speech-to-Text:

```python
# Automatic based on file extension
audio_extensions = ['wav', 'mp3', 'opus', 'ogg', 'flac', 'wma', 'aac', 'webm']
```

---

## Local Development

### Setup

1. **Get remote settings:**
   ```powershell
   ./scripts/getRemoteSettings.ps1
   ```

2. **Verify `local.settings.json`** contains required connection strings

3. **Start the function app:**
   ```powershell
   ./scripts/startLocal.ps1
   ```

### Local Settings Requirements

```json
{
  "IsEncrypted": false,
  "Values": {
    "AzureWebJobsStorage": "...",
    "FUNCTIONS_WORKER_RUNTIME": "python",
    "AZURE_FUNCTIONS_ENVIRONMENT": "Development",
    "APP_CONFIGURATION_URI": "https://{appconfig}.azconfig.io",
    "DataStorage": "..."
  }
}
```

### Testing

Use `test_client.ipynb` to test the HTTP trigger endpoint locally or against deployed function.

---

## Troubleshooting

#### EventGrid Subscription Creation Fails

**Symptom:** postDeploy script fails to create subscription

**Solutions:**
1. Wait 2-3 minutes after deployment for function to initialize
2. Re-run: `./scripts/postDeploy.ps1`
3. Check function app is running: Azure Portal > Function App > Functions

#### Function Cold Start Timeout

**Symptom:** Webhook validation timeout during EventGrid subscription

**Solution:** The postDeploy script includes warmup requests. If still failing, increase warmup iterations or use Dedicated hosting plan.

#### Missing blobs_extension Key

**Symptom:** Cannot retrieve system key from function app

**Solutions:**
1. Ensure function code is deployed (`azd deploy`)
2. Verify blob trigger function exists in portal
3. Check function app logs for initialization errors

#### Authentication Errors

**Symptom:** 401/403 errors accessing Azure services

**Solutions:**
1. Verify managed identity role assignments in Azure Portal
2. Check App Configuration connection
3. For local dev: Ensure Azure CLI is logged in (`az login`)

### Diagnostic Commands

```powershell
# Check function app status
az functionapp show -n $functionAppName -g $resourceGroup --query state

# List functions
az functionapp function list -n $functionAppName -g $resourceGroup

# View system keys
az functionapp keys list -n $functionAppName -g $resourceGroup

# Check Event Grid subscription
az eventgrid system-topic event-subscription list -g $resourceGroup --system-topic-name $topicName
```

---

## Recent Changes & Improvements

### Infrastructure Fixes & Enhancements (April 2025)

1. **AI Foundry PE Race Condition Fix**
   - Moved private endpoint creation out of the AVM module into a dedicated `aiFoundryPe` module
   - Added `dependsOn: [aiFoundry]` to prevent `AccountProvisioningStateInvalid` errors
   - Extended `private-endpoint.bicep` to support multiple DNS zones via new `dnsZoneIds` array parameter

2. **FlexConsumption Subnet Delegation Fix**
   - VNet module now conditionally sets `Microsoft.App/environments` delegation for FlexConsumption
   - Falls back to `Microsoft.Web/serverFarms` for Dedicated plans
   - Added `functionAppHostPlan` parameter to the VNet module

3. **functionAppHostPlan Default to FlexConsumption**
   - Changed default from no value (prompted) to `'FlexConsumption'`
   - Works on MCAP subscriptions where Dedicated plans are blocked by ANT quota restrictions

4. **aoaiLocation Simplified**
   - Removed the hardcoded `@allowed` list (was causing format mismatch between `eastus2` and `East US 2`)
   - Now defaults to same `location` as the resource group
   - Can be overridden via `AOAI_LOCATION` environment variable

5. **VM Size Configurable via Environment Variable**
   - Added `AZURE_VM_SIZE` env var mapped to `vmSize` parameter
   - Wired through `main.parameters.json`, `deploy.sh`, and `deploy.ps1`
   - Default: `Standard_D8s_v5`

6. **VM AntiMalware Extension Toggle**
   - New `vmAntiMalware` parameter (default: `true`) with `AZURE_VM_ANTIMALWARE` env var
   - Set to `false` for network-isolated environments without outbound internet to prevent `VMAgentStatusCommunicationError`

### Infrastructure (Bicep) — Original

1. **AI Foundry Migration**
   - Migrated from standalone Azure OpenAI to AI Foundry AVM pattern
   - Uses `br/public:avm/ptn/ai-ml/ai-foundry:0.6.0`
   - `includeAssociatedResources: false` to use existing resources

2. **Function Storage AVM**
   - Migrated to `br/public:avm/res/storage/storage-account:0.25.0`
   - Disabled shared key access (`allowSharedKeyAccess: false`)
   - Managed identity authentication only

3. **Event Grid System Topic**
   - System topic created in Bicep for reliability
   - Event subscription created in postDeploy script
   - Outputs `BRONZE_SYSTEM_TOPIC_NAME` for script consumption

4. **Hosting Plan Flexibility**
   - Supports both `Dedicated` and `FlexConsumption`
   - Automatic app settings based on plan type
   - SKU validation by plan type

### Pipeline Code

1. **Multi-Modal Support**
   - Added `callFoundryMultiModal.py` for PDF vision processing
   - PDF pages converted to base64 images using PyMuPDF

2. **Audio Processing**
   - Added `speechToText.py` for audio transcription
   - Uses Azure AI Services batch transcription API

3. **Configuration Module**
   - Centralized configuration via Azure App Configuration
   - Automatic Key Vault secret resolution
   - Environment-aware credential selection

4. **Improved Blob Trigger**
   - Uses EventGrid source for reliable triggering
   - Structured `BlobMetadata` class for consistent data passing

### Scripts

1. **postDeploy.ps1/sh**
   - Creates EventGrid subscription after function deployment
   - Includes function warmup to prevent webhook timeout
   - Idempotent - checks for existing subscription

2. **getRemoteSettings.ps1/sh**
   - Downloads function app settings for local development
   - Automatically formats for `local.settings.json`

---

## Additional Resources

- [Azure Durable Functions Documentation](https://docs.microsoft.com/en-us/azure/azure-functions/durable/)
- [Azure AI Foundry Documentation](https://learn.microsoft.com/en-us/azure/ai-studio/)
- [Event Grid Blob Storage Events](https://docs.microsoft.com/en-us/azure/event-grid/event-schema-blob-storage)
- [Azure Verified Modules (AVM)](https://aka.ms/avm)

---

*This document was generated based on the current state of the ADPF solution as of December 2024.*
