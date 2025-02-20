import os
import logging
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient
import base64
import json
ACCOUNT_NAME = os.getenv("AzureWebJobsStorage__accountName")
BLOB_ENDPOINT=f"https://{ACCOUNT_NAME}.blob.core.windows.net"

# if os.getenv("IS_LOCAL"):
#     BLOB_ENDPOINT = os.getenv("BLOB_ENDPOINT")



blob_credential = DefaultAzureCredential()  # Uses managed identity or local login

token = blob_credential.get_token("https://storage.azure.com/.default")

# Decode the token for inspection
jwt_token = token.token.split(".")
header = json.loads(base64.urlsafe_b64decode(jwt_token[0] + "=="))
payload = json.loads(base64.urlsafe_b64decode(jwt_token[1] + "=="))

logging.info("=== Token Header ===")
logging.info(json.dumps(header, indent=4))

logging.info("\n=== Token Payload ===")
logging.info(json.dumps(payload, indent=4))
# Decode the token for inspection
jwt_token = token.token.split(".")
header = json.loads(base64.urlsafe_b64decode(jwt_token[0] + "=="))
payload = json.loads(base64.urlsafe_b64decode(jwt_token[1] + "=="))

print("=== Token Header ===")
print(json.dumps(header, indent=4))

print("\n=== Token Payload ===")
print(json.dumps(payload, indent=4))



blob_service_client = BlobServiceClient(account_url=BLOB_ENDPOINT, credential=blob_credential)

logging.info(f"BLOB_ENDPOINT: {BLOB_ENDPOINT}")

def write_to_blob(container_name, blob_path, data):

    blob_client = blob_service_client.get_blob_client(container=container_name, blob=blob_path)
    blob_client.upload_blob(data, overwrite=True)

def get_blob_content(container_name, blob_path):

    blob_client = blob_service_client.get_blob_client(container=container_name, blob=blob_path)
    # Download the blob content
    blob_content = blob_client.download_blob().readall()
    return blob_content

def list_blobs(container_name):
    container_client = blob_service_client.get_container_client(container_name)
    blob_list = container_client.list_blobs()
    return blob_list

def delete_all_blobs_in_container(container_name):
    container_client = blob_service_client.get_container_client(container_name)
    blob_list = container_client.list_blobs()
    for blob in blob_list:
        blob_client = container_client.get_blob_client(blob.name)
        blob_client.delete_blob()