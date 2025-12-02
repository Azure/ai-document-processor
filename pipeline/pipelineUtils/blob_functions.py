import os
import logging
from dataclasses import dataclass
import json

from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient

from configuration import Configuration
config = Configuration()

BLOB_ENDPOINT=config.get_value("DATA_STORAGE_ENDPOINT")

# if os.environ.get("AZURE_FUNCTIONS_ENVIRONMENT") == "Development":
#     BLOB_ENDPOINT = os.getenv("AzureWebJobsStorage")

token = config.credential.get_token("https://storage.azure.com/.default")

blob_service_client = BlobServiceClient(account_url=BLOB_ENDPOINT, credential=config.credential)

@dataclass
class BlobMetadata:
    name: str
    uri: str
    container: str

    def to_dict(self):
        return {"name": self.name, "uri": self.uri, "container": self.container}

    def to_json(self):
        return json.dumps(self.to_dict(), ensure_ascii=False)
    

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