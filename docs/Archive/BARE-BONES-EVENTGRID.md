# PDF Processor: Extending Microsoft's Flex Consumption Quickstart

This guide starts with **Microsoft's official EventGrid blob trigger quickstart** and adds Document Intelligence for PDF→text conversion.

**The approach:** Clone their working sample, then add our modifications.

---

## Step 1: Clone Microsoft's Official Quickstart

```bash
# Clone the official Microsoft sample
azd init --template Azure-Samples/functions-quickstart-python-azd-eventgrid-blob

# This creates a working Flex Consumption + EventGrid blob trigger project
```

This gives you a **known-working** project with:
- ✅ Flex Consumption Function App
- ✅ EventGrid System Topic (created via Bicep)
- ✅ Event subscription (created via CLI in post-up script)
- ✅ User-Assigned Managed Identity
- ✅ All required RBAC roles

---

## Step 2: Understand What You Get

After cloning, you'll have this structure:

```
functions-quickstart-python-azd-eventgrid-blob/
├── src/
│   ├── function_app.py          # Simple blob trigger
│   ├── requirements.txt         # Just azure-functions
│   └── host.json
├── infra/
│   ├── main.bicep               # All infrastructure
│   ├── main.parameters.json
│   └── abbreviations.json
├── scripts/
│   ├── post-up.ps1              # Creates EventGrid subscription (CLI)
│   └── post-up.sh
└── azure.yaml
```

**Their `function_app.py`:**
```python
import logging
import azure.functions as func

app = func.FunctionApp()

@app.blob_trigger(
    arg_name="blob",
    path="samples-workitems/{name}",
    connection="Storage",
    source=func.BlobSource.EVENT_GRID  # The key setting!
)
def process_blob(blob: func.InputStream):
    logging.info(f"Blob trigger processed blob\nName: {blob.name}\nSize: {blob.length} bytes")
```

**Their `scripts/post-up.ps1`:** (simplified)
```powershell
# Get blobs_extension key
$blobs_extension = az functionapp keys list -n $funcApp -g $rg --query "systemKeys.blobs_extension" -o tsv

# Create event subscription via CLI
az eventgrid system-topic event-subscription create `
    -n "blob-subscription" `
    -g $rg `
    --system-topic-name $topic `
    --endpoint-type webhook `
    --endpoint "https://$funcApp.azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.process_blob&code=$blobs_extension" `
    --included-event-types Microsoft.Storage.BlobCreated
```

---

## Step 3: Modifications for PDF Processing

We need to make **4 changes** to add Document Intelligence:

### Change 1: Add Document Intelligence to Bicep

**File:** `infra/main.bicep`

Add this module (after the storage account):

```bicep
// Document Intelligence (for PDF OCR)
module documentIntelligence 'br/public:avm/res/cognitive-services/account:0.10.2' = {
  name: 'documentIntelligence'
  scope: rg
  params: {
    name: '${abbrs.cognitiveServicesAccounts}${resourceToken}'
    location: location
    tags: tags
    kind: 'FormRecognizer'
    sku: 'S0'
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

// RBAC: Cognitive Services User
module cogServicesUser 'br/public:avm/ptn/authorization/resource-role-assignment:0.1.1' = {
  name: 'cogServicesUser'
  scope: rg
  params: {
    principalId: managedIdentity.outputs.principalId
    resourceId: documentIntelligence.outputs.resourceId
    roleDefinitionId: 'a97b65f3-24c7-4388-baec-2e87135dc908'
    principalType: 'ServicePrincipal'
  }
}
```

Add to the function app's `appSettingsKeyValuePairs`:
```bicep
DOCUMENT_INTELLIGENCE_ENDPOINT: documentIntelligence.outputs.endpoint
```

Add an output container for processed files:
```bicep
blobServices: {
  containers: [
    { name: 'samples-workitems' }  // Existing
    { name: 'processed' }           // Add this for output
  ]
}
```

Add abbreviation to `abbreviations.json`:
```json
"cognitiveServicesAccounts": "cog-"
```

### Change 2: Update requirements.txt

**File:** `src/requirements.txt`

```
azure-functions
azure-identity
azure-ai-documentintelligence
azure-storage-blob
```

### Change 3: Update function_app.py

**File:** `src/function_app.py`

```python
import logging
import os
import azure.functions as func
from azure.ai.documentintelligence import DocumentIntelligenceClient
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

app = func.FunctionApp()


@app.blob_trigger(
    arg_name="blob",
    path="samples-workitems/{name}",
    connection="Storage",
    source=func.BlobSource.EVENT_GRID
)
def process_blob(blob: func.InputStream):
    """
    Triggered when a file is uploaded to samples-workitems container.
    If it's a PDF, extract text and save to processed container.
    """
    blob_name = blob.name
    logging.info(f"Processing: {blob_name}, Size: {blob.length} bytes")
    
    # Only process PDFs
    if not blob_name.lower().endswith('.pdf'):
        logging.info(f"Not a PDF, skipping: {blob_name}")
        return
    
    try:
        credential = DefaultAzureCredential()
        
        # Get environment variables
        doc_intel_endpoint = os.environ["DOCUMENT_INTELLIGENCE_ENDPOINT"]
        storage_account = os.environ["Storage__accountName"]
        
        # Read PDF content
        pdf_content = blob.read()
        
        # Extract text using Document Intelligence
        doc_client = DocumentIntelligenceClient(
            endpoint=doc_intel_endpoint,
            credential=credential
        )
        
        poller = doc_client.begin_analyze_document(
            model_id="prebuilt-read",
            body=pdf_content,
            content_type="application/pdf"
        )
        result = poller.result()
        
        # Collect all text
        extracted_text = ""
        for page in result.pages:
            for line in page.lines:
                extracted_text += line.content + "\n"
        
        logging.info(f"Extracted {len(extracted_text)} characters")
        
        # Save to processed container
        blob_service = BlobServiceClient(
            account_url=f"https://{storage_account}.blob.core.windows.net",
            credential=credential
        )
        
        # Change .pdf to .txt
        output_name = blob_name.replace("samples-workitems/", "").rsplit(".", 1)[0] + ".txt"
        
        processed_container = blob_service.get_container_client("processed")
        processed_container.upload_blob(
            name=output_name,
            data=extracted_text,
            overwrite=True
        )
        
        logging.info(f"Saved to processed/{output_name}")
        
    except Exception as e:
        logging.error(f"Error: {str(e)}")
        raise
```

### Change 4: Filter for PDFs in post-up script

**File:** `scripts/post-up.ps1`

Add this to the event subscription command:
```powershell
--subject-ends-with ".pdf"
```

---

## Step 4: Deploy

```bash
# Login
azd auth login

# Deploy (prompts for environment name and location)
azd up
```

---

## Step 5: Test

```bash
# Get storage account name
$storage = azd env get-value STORAGE_ACCOUNT_NAME

# Upload a PDF
az storage blob upload `
    --account-name $storage `
    --container-name samples-workitems `
    --name test.pdf `
    --file C:\path\to\test.pdf `
    --auth-mode login

# Check output (wait a few seconds for processing)
az storage blob list `
    --account-name $storage `
    --container-name processed `
    --auth-mode login `
    --output table
```

---

## Key Differences: Microsoft's Approach vs Our ADP Approach

| Aspect | Microsoft Quickstart | Our ADP Project |
|--------|---------------------|-----------------|
| **EventGrid Topic** | ✅ Uses System Topic (Bicep) | ❌ No system topic |
| **Event Subscription** | CLI in post-up script | Bicep module + retries |
| **Retry Logic** | ❌ None | ✅ 3 retries with warmup |
| **Error Handling** | Script fails | Graceful fallback + Portal instructions |
| **Complexity** | Simple, trusts it works | More robust, handles edge cases |

**Why start with Microsoft's approach:**
- It's simpler and easier to understand
- It's the official pattern
- If it breaks, you can point to Microsoft's docs
- You can add complexity (retries, etc.) later if needed

---

## If EventGrid Subscription Fails

The CLI command may fail if the function is cold. Microsoft's quickstart doesn't handle this, so you may need to create it manually:

1. **Azure Portal** → Storage Account → Events
2. **+ Event Subscription**
3. Fill in:
   - Name: `blob-subscription`
   - Event Types: ✅ Blob Created only
   - Endpoint Type: Azure Function
   - Endpoint: Select your function → `process_blob`
4. **Filters tab:**
   - Subject Begins With: `/blobServices/default/containers/samples-workitems/`
   - Subject Ends With: `.pdf`
5. **Create**

---

## Clean Up

```bash
azd down
```

---

## Summary

| Step | What You Do |
|------|-------------|
| 1 | Clone Microsoft's quickstart with `azd init --template` |
| 2 | Add Document Intelligence module to Bicep |
| 3 | Update requirements.txt with azure-ai-documentintelligence |
| 4 | Replace function_app.py with PDF processing logic |
| 5 | Add `.pdf` filter to post-up script |
| 6 | Deploy with `azd up` |

You're building on top of a known-working sample, so the EventGrid/Flex Consumption integration is already solved.

---

## References

- **Official Quickstart:** https://github.com/Azure-Samples/functions-quickstart-python-azd-eventgrid-blob
- **Flex Consumption Docs:** https://learn.microsoft.com/en-us/azure/azure-functions/flex-consumption-plan
- **EventGrid Blob Trigger:** https://learn.microsoft.com/en-us/azure/azure-functions/functions-event-grid-blob-trigger
- **Document Intelligence:** https://learn.microsoft.com/en-us/azure/ai-services/document-intelligence/

---

*Created: December 17, 2025*
