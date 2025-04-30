import os
import logging
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

from configuration import Configuration
config = Configuration()

ACCOUNT_NAME = config.get_value("STORAGE_ACCOUNT_NAME")
BLOB_ENDPOINT=f"https://{ACCOUNT_NAME}.blob.core.windows.net"

# if os.getenv("IS_LOCAL"):
#     BLOB_ENDPOINT = os.getenv("BLOB_ENDPOINT")

token = config.credential.get_token("https://storage.azure.com/.default")

blob_service_client = BlobServiceClient(account_url=BLOB_ENDPOINT, credential=config.credential)

logging.info(f"BLOB_ENDPOINT: {BLOB_ENDPOINT}")

def write_to_blob(container_name, blob_path, data):

    blob_client = blob_service_client.get_blob_client(container=container_name, blob=blob_path)
    blob_client.upload_blob(data, overwrite=True)
    return True

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