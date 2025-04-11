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
![image](https://github.com/user-attachments/assets/47a64ff8-1185-48ec-904f-2cebefc26687)


![image](https://github.com/user-attachments/assets/4ef01588-fe21-46da-85cf-23c532cebee0)


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
  - azd auth login
  - az login
  - azd up
  - Enter your forked GH repo link `https://github.com/{your_user_name}/llm-doc-processing`
  - Enter your User Principal ID when prompted
  - To get your User principal ID run `az ad signed-in-user show --query id -o tsv`
  - Select whether you would like to deploy a frontend UI. The UI is not necessary, but is helpful for quick testing of prompts and seeing pipeline progress.
  - Select a format to manage your prompts. You can either use a YAML file to manage your prompts or Cosmos DB. If you are deploying the frontend UI we recommend Cosmos.

### (Optional) Deploy front-end UI (Static Web App) from CLI
1. Check SWA configuration `swa-cli.config.json`
   - Ensure SWA CLI is intalled `npm install -g @azure/static-web-apps-cli`
   - Ensure apiLocation = ""
   - Resulting swa-cli.config should look like:
   - `{
        "$schema": "https://aka.ms/azure/static-web-apps-cli/schema",
        "configurations": {
          "ai-document-processor-v1": {
            "appLocation": "frontend",
            "apiLocation": "",
            "outputLocation": "dist",
            "dataApiLocation": "frontend/swa-db-connections",
            "apiLanguage": "python",
            "apiVersion": "3.8",
            "appBuildCommand": "npm run build",
            "run": "npm run dev",
            "appDevserverUrl": "http://localhost:5173"
          }
        }
      }`
    - If changes are desired `swa init` may be run
3. `swa build`
4. `swa deploy --env Production -d {deployment_token}`
     - Retrieve deployment token from overview page of the static web app in Azure portal under "Manage Deployment Token"

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
- Check for exceptions using a query in App Insights

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

