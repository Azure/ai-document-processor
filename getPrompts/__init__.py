import os
import json
import azure.functions as func
from azure.storage.blob import BlobServiceClient
from azure.identity import DefaultAzureCredential
import logging
import yaml
from utils.prompts import load_prompts

# Get environment variables
STORAGE_ACCOUNT_NAME = os.getenv("AzureWebJobsStorage__accountName")
PROMPTS_CONTAINER_NAME = "prompts"  # Replace with your container name
PROMPTS_BLOB_NAME = "prompts.yaml"  # Replace with your blob name

# Create BlobServiceClient using Managed Identity
credential = DefaultAzureCredential()
blob_service_client = BlobServiceClient(
    f"https://{STORAGE_ACCOUNT_NAME}.blob.core.windows.net", credential=credential
)

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Python HTTP trigger function processed a request getPrompts.")
    try:
        prompts = load_prompts()  # Ensure prompts are loaded
        logging.info(f"Prompts loaded successfully \n {prompts}")
        # prompts = yaml.safe_load(blob_content)
        prompts_json = json.dumps(prompts, indent=4)

        # Return JSON response
        return func.HttpResponse(json.dumps(prompts_json), mimetype="application/json")

    except Exception as e:
        logging.error(f"Error fetching prompts: {str(e)}")
        return func.HttpResponse(f"Error: {str(e)}", status_code=500)
