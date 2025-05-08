# AI Document Processor (ADP)

## Description
AI Document Processor Accelerator is designed to help companies leverage LLMs to automate document and file processing tasks. The accelerator uses bicep templates to provision Azure Function App, Storage account, and static web app to manage your documents life cycle from raw PDF, word doc, or .mp3, extract meaningful entities and insights, and write an output report, CSV, or JSON to a blob storage container. 

## Business Value
- *Developer Foundation* -  AI Document Processor is intended to serve as an initial foundation to build your workflow on top of. Developers can write custom logic within the azure functions and leverage existing utility functions to write to blob and call Azure OpenAI models.
- *Business User UI* - Business users can leverage the UI to update prompts and files to immediately test the results.
- *Automated Infrastructure Provisioning* - The bicep templates spin up the required infrastructure and builds a deployment pipeline for Azure Functions and the Static Web App 
- *RBAC Configuration* - The bicep templates spin up infrastructure with managed identities and appropriate access to reduce initial overhead tasks such as granting permissions between services. 

## Resources
- Azure OpenAI
- Azure Function App
- App Service Plan
- Azure Storage Account
- Azure Static Web App
- Key Vault
- Application insights
- Azure Cognitive Services (Multi-Service)
- Cosmos DB

## Architecture

### Main Components
![image](https://github.com/user-attachments/assets/47a64ff8-1185-48ec-904f-2cebefc26687)

### Data Flow
![image](https://github.com/user-attachments/assets/5721a5be-2f93-44a5-a259-928bfd1b5e83)

### ZTA Network Architecture
![image](https://github.com/user-attachments/assets/a761cb68-8603-44c2-acd6-b20a9055c57d)



## Pre-Requisites
- az cli
- azd cli
- npm 9.x.x
- node 18.x.x
- Python 3.11
  
## Deployment Instructions

1. Fork repo to your GH account
2. Clone your forked repo
3. To deploy bicep template run:
  - az login
  - azd auth login
  - azd up
  - Enter your User Principal ID when prompted
  - To get your User principal ID run `az ad signed-in-user show --query id -o tsv`
  - Select whether you would like to deploy a frontend UI. The UI is not necessary, but is helpful for quick testing of prompts and seeing pipeline progress.

### Update the Pipeline for a customer's specific use case
This repository is intended to set up the scaffolding for an Azure OpenAI pipeline. The developer is expected to update the code in the `pipeline/activities` and `pipeline/function_app.py` to meet the customer's needs.
- `pipeline/function_app.py` - contains the standard logic for handling HTTP requests and invoking the pipeline leveraging [Azure Durable functions function chaining pattern](https://learn.microsoft.com/en-us/azure/azure-functions/durable/durable-functions-sequence?tabs=csharp). This file controls the high level orchestration logic for each step in the pipeline, while the logic for each step is contained within the `activities` directory
- `pipeline/activities` - contains each of the steps in the pipeline
  - runDocIntel.py - runs an OCR job on the blob, returns a text string with the content
  - callAoai.py - retrieves prompt instructions and sends prompt instructions + text content from previous step to AzureOpenAI to generate a JSON output that extracts key content from the input blob
  - writeToBlob.py - writes the resulting JSON to blob storage to be consumed by a frontend UI or downloaded as a report

The intent is for this base use case to be updated by the developer to meet the specific customer's use case.

### Run the Pipeline
The default pipeline processes PDFs from the azure storage account bronze container by extracting their text using Doc Intelligence, sending the text results to Azure OpenAI along with prompt instructions to create a summary JSON. Write the output JSON to blob storage gold container. The system prompt and user prompt can be updated either in Cosmos DB or in a prompts.yaml file depending on whether you deployed with or without a frontend UI.

#### Without frontend UI
- Verify Function App deployment. Navigate to the function app overview page and confirm functions are present
- Update the `prompts.yaml` file in the prompts container of the storage account with your desired prompt instructions for the pipeline
- Send a POST request to the http_start endpoint

`curl -v -X POST "http://<FUNCTION_APP_NAME>/api/orchestrators/orchestrator?code=<AUTH_KEY>" \
-H "Content-Type: application/json" \
-d '{
  "blobs": [
    {
      "name": "<BLOB_NAME>",
      "url": "https://<STORAGE_ACCOUNT_NAME>.blob.core.windows.net/bronze?<SAS_TOKEN>",
      "container": "bronze"
    }
  ]
}'`
- Pipeline should take ~30 sec to execute
- Results written to gold container of the storage account
- Monitor progress of pipeline using Log Stream

#### With frontend UI
- Open Static Web App URL (find link on Static Web App overview page)
- Upload desired files
- Update system prompts and user prompts in the Prompt Editor. This will update the backend Cosmos DB, which will be used in the pipeline.
- Click "Start Workflow" to start the pipeline
- Messages will populate to indicate the success or failure of the job

### Troubleshooting
- Leverage Log Stream to get real-time logging, which will give visibility into each step in the pipeline
- Leverage Log Analytics Workspace to run queries and see exceptions that occurred in the app
- For deployment issues, use the Development Tools SSH console to inspect the internal file system and get deployment logs

##  MIT License
https://opensource.org/license/MIT 

Copyright (c) 2025 Mark Remmey

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

