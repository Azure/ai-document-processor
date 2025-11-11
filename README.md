# AI Document Processor (ADP)

## Description
AI Document Processor Accelerator is designed to help companies leverage LLMs to automate document and file processing tasks. The accelerator uses bicep templates to provision Azure Function App, Storage account,  to manage your documents life cycle from raw PDF, word doc, or .mp3, extract meaningful entities and insights, and write an output report, CSV, or JSON to a blob storage container. 

## Business Value
- *Developer Foundation* -  AI Document Processor is intended to serve as an initial foundation to build your workflow on top of. Developers can write custom logic within the azure functions and leverage existing utility functions to write to blob and call Azure OpenAI models.
- *Automated Infrastructure Provisioning* - The bicep templates spin up the required infrastructure and builds a deployment pipeline for Azure Functions
- *RBAC Configuration* - The bicep templates spin up infrastructure with managed identities and appropriate access to reduce initial overhead tasks such as granting permissions between services. 

## Resources
- Azure OpenAI
- Azure Function App
- App Service Plan
- Azure Storage Account
- Key Vault
- Application insights
- Azure Cognitive Services (Multi-Service)
- Cosmos DB

## Architecture

### Main Components
<img width="835" height="535" alt="image" src="https://github.com/user-attachments/assets/e23c9da1-8102-4d1d-8fa7-ca36f4511230" />


### Data Flow
<img width="935" height="617" alt="image" src="https://github.com/user-attachments/assets/8d7d4aad-961f-4d1a-a6ea-660dbdf6fc43" />

### ZTA Network Architecture
<img width="1840" height="935" alt="image" src="https://github.com/user-attachments/assets/41adbe41-c7de-4cbe-84a8-4110c28f40e4" />



## Pre-Requisites
- az cli
- azd cli
- Python 3.11+
- azure-functiosn-core-tools
  
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
The default pipeline processes PDFs from the azure storage account bronze container by extracting their text using Doc Intelligence, sending the text results to Azure OpenAI along with prompt instructions to create a summary JSON. Write the output JSON to blob storage gold container. The system prompt and user prompt can be updated in a prompts.yaml file depending on whether you deployed with or without a frontend UI.

- Verify Function App deployment. Navigate to the function app overview page and confirm functions are present
- Update the `prompts.yaml` file in the prompts container of the storage account with your desired prompt instructions for the pipeline
- Use test_client.ipynb to test your function app endpoint
- Pipeline should take ~30 sec to execute
- Results written to silver container of the storage account
- Monitor progress of pipeline using Log Stream

## Start the function locally
- Linux / WSL
  - Ensure Storage accounts enable shared key access (Azure Portal > Storage Account > Configuration). May need to refresh page to ensure update was effective
  - Get Remote settings from the function app: `./scripts/getRemoteSettings.sh`\
  - Check to ensure that Blob Connections strings are present in local.settings.json
  - Start the venv and the function app locally `./scripts/startLocal.sh`

- Windows / PWSH
  - Ensure Storage accounts enable shared key access (Azure Portal > Storage Account > Configuration). May need to refresh page to ensure update was effective
  - Get Remote settings from the function app: `./scripts/getRemoteSettings.ps1`
  - Check to ensure that Blob Connections strings are present in local.settings.json
  - Start the venv and the function app locally `./scripts/startLocal.ps1`


### Troubleshooting
- Leverage Log Stream to get real-time logging, which will give visibility into each step in the pipeline
- Leverage Log Analytics Workspace to run queries and see exceptions that occurred in the app
- For deployment issues, use the Development Tools SSH console to inspect the internal file system and get deployment logs
- Consider running `azd up --debug 2>&1 | tee debug.log` to output detailed deployment logs and save to a local file for inspection


### Common Issues
1. "The deployment pipeline appears to complete without error, but no functions appear in my Azure portal.
- Check Logs > Exceptions
- If there is an issue in the Configuration.py, it is possible that the function is not authenticating successfully with App Config.
  - Check that appropriate IAM roles are assigned
  - Check the DefaultAzureCredential settings and ensure that they make sense
- Attempt to deploy the function app locally to confirm that there are no version or ModuleNotFound errors preventing start up.

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

