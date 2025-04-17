import os
import json
import datetime
import azure.functions as func
from azure.storage.blob import BlobServiceClient, generate_blob_sas, BlobSasPermissions
import logging
# Get environment variables
from configuration import Configuration
config = Configuration()

STORAGE_ACCOUNT_NAME = config.get_value("STORAGE_ACCOUNT_NAME")
USE_SAS_TOKEN = config.get_value("USE_SAS_TOKEN") == "true"
HOURS = int(config.get_value("SAS_TOKEN_EXPIRY_HOURS"))

# Create BlobServiceClient using Managed Identity
blob_service_client = BlobServiceClient(
    f"https://{STORAGE_ACCOUNT_NAME}.blob.core.windows.net", credential=config.credential
)

delegation_key = blob_service_client.get_user_delegation_key(
    key_start_time=datetime.datetime.utcnow(),
    key_expiry_time=datetime.datetime.utcnow() + datetime.timedelta(hours=HOURS)
)

def generate_sas_token(container_name, blob_name):
    """Generate a SAS token with read & write access for a blob."""
    sas_token = generate_blob_sas(
        account_name=STORAGE_ACCOUNT_NAME,
        container_name=container_name,
        blob_name=blob_name,
        user_delegation_key=delegation_key,  # Managed Identity handles authentication
        permission=BlobSasPermissions(read=True, write=True),  # Read & Write
        expiry=datetime.datetime.utcnow() + datetime.timedelta(hours=HOURS)  # 1-hour expiry
    )

    blob_client = blob_service_client.get_blob_client(container_name, blob_name)

    if USE_SAS_TOKEN == "true" or USE_SAS_TOKEN == True:
        # Generate a SAS URL for the blob
        return f"{blob_client.url}?{sas_token}"
    else:
        # Generate a URL without SAS token for Managed Identity access
        return blob_client.url

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
