import os
import json
import datetime
import azure.functions as func
from azure.storage.blob import BlobServiceClient, generate_blob_sas, BlobSasPermissions
from azure.identity import DefaultAzureCredential
import logging
# Get environment variables
STORAGE_ACCOUNT_NAME = os.getenv("AzureWebJobsStorage__accountName")

# Create BlobServiceClient using Managed Identity
credential = DefaultAzureCredential()
blob_service_client = BlobServiceClient(
    f"https://{STORAGE_ACCOUNT_NAME}.blob.core.windows.net", credential=credential
)

delegation_key = blob_service_client.get_user_delegation_key(
    key_start_time=datetime.datetime.utcnow(),
    key_expiry_time=datetime.datetime.utcnow() + datetime.timedelta(hours=1)
)

def generate_sas_token(container_name, blob_name):
    """Generate a SAS token with read & write access for a blob."""
    sas_token = generate_blob_sas(
        account_name=STORAGE_ACCOUNT_NAME,
        container_name=container_name,
        blob_name=blob_name,
        user_delegation_key=delegation_key,  # Managed Identity handles authentication
        permission=BlobSasPermissions(read=True, write=True),  # Read & Write
        expiry=datetime.datetime.utcnow() + datetime.timedelta(hours=1)  # 1-hour expiry
    )

    blob_client = blob_service_client.get_blob_client(container_name, blob_name)
    return f"{blob_client.url}?{sas_token}"

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Python HTTP trigger function processed a request for getBlobsByContainer.")
    try:
        container_names = ["bronze", "silver", "gold"]
        blobs_by_container = {}

        for container in container_names:
            container_client = blob_service_client.get_container_client(container)
            blobs_with_sas = [
                {
                    "name": blob.name,
                    "url": generate_sas_token(container, blob.name)  # Get SAS URL for each blob
                }
                for blob in container_client.list_blobs()
            ]
            blobs_by_container[container] = blobs_with_sas

        return func.HttpResponse(json.dumps(blobs_by_container), mimetype="application/json")

    except Exception as e:
        return func.HttpResponse(f"Error: {str(e)}", status_code=500)
