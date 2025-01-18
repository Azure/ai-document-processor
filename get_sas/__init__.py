import os
import json
import datetime
import azure.functions as func
from azure.storage.blob import BlobServiceClient, generate_blob_sas, BlobSasPermissions
from azure.identity import DefaultAzureCredential

# Get environment variables
STORAGE_ACCOUNT_NAME = os.getenv("AzureWebJobsStorage__accountName")

# Create BlobServiceClient using Managed Identity
credential = DefaultAzureCredential()
blob_service_client = BlobServiceClient(
    f"https://{STORAGE_ACCOUNT_NAME}.blob.core.windows.net", credential=credential
)

def generate_sas_token(container_name, blob_name):
    """Generate a SAS token with read & write access for a blob."""
    sas_token = generate_blob_sas(
        account_name=STORAGE_ACCOUNT_NAME,
        container_name=container_name,
        blob_name=blob_name,
        account_key=None,  # Managed Identity handles authentication
        permission=BlobSasPermissions(read=True, write=True),  # Read & Write
        expiry=datetime.datetime.utcnow() + datetime.timedelta(hours=1)  # 1-hour expiry
    )

    blob_client = blob_service_client.get_blob_client(container_name, blob_name)
    return f"{blob_client.url}?{sas_token}"

def main(req: func.HttpRequest) -> func.HttpResponse:
    try:
        req_body = req.get_json()
        container_name = req_body.get("container")
        blob_name = req_body.get("blob")

        if not container_name or not blob_name:
            return func.HttpResponse("Missing 'container' or 'blob' parameter.", status_code=400)

        sas_url = generate_sas_token(container_name, blob_name)

        return func.HttpResponse(json.dumps({"sas_url": sas_url}), mimetype="application/json")

    except Exception as e:
        return func.HttpResponse(f"Error: {str(e)}", status_code=500)
