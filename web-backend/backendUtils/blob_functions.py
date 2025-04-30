import os
import logging
from azure.identity import DefaultAzureCredential
from azure.storage.blob import BlobServiceClient
import base64
import json

from configuration import Configuration
config = Configuration()

ACCOUNT_NAME = config.get_value("STORAGE_ACCOUNT_NAME")
BLOB_ENDPOINT=f"https://{ACCOUNT_NAME}.blob.core.windows.net"

# if config.get_value("IS_LOCAL"):
#     BLOB_ENDPOINT = config.get_value("BLOB_ENDPOINT")

blob_credential = config.credential  # Uses managed identity or local login

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
    """
    Write data to an Azure Blob Storage blob.
    
    Args:
        container_name (str): Name of the container
        blob_path (str): Path to the blob within the container
        data: Data to write to the blob
        
    Returns:
        None
        
    Raises:
        Exception: If there's an error writing to the blob
    """
    try:
        blob_client = blob_service_client.get_blob_client(container=container_name, blob=blob_path)
        blob_client.upload_blob(data, overwrite=True)
    except Exception as e:
        logging.error(f"Error writing to blob {blob_path} in container {container_name}: {str(e)}")
        raise


def get_blob_content(container_name, blob_path):
    """
    Retrieve the content of a blob from Azure Blob Storage.
    
    Args:
        container_name (str): Name of the container
        blob_path (str): Path to the blob within the container
        
    Returns:
        bytes: The content of the blob
        
    Raises:
        Exception: If there's an error retrieving the blob content
    """
    try:
        blob_client = blob_service_client.get_blob_client(container=container_name, blob=blob_path)
        # Download the blob content
        blob_content = blob_client.download_blob().readall()
        return blob_content
    except Exception as e:
        logging.error(f"Error retrieving content from blob {blob_path} in container {container_name}: {str(e)}")
        raise

def list_blobs(container_name):
    """
    List all blobs in a container.
    
    Args:
        container_name (str): Name of the container
        
    Returns:
        list: A list of blob objects in the container
        
    Raises:
        Exception: If there's an error listing the blobs
    """
    try:
        container_client = blob_service_client.get_container_client(container_name)
        blob_list = container_client.list_blobs()
        return blob_list
    except Exception as e:
        logging.error(f"Error listing blobs in container {container_name}: {str(e)}")
        raise

def delete_blob(container_name, blob_name):
    """
    Delete a specific blob from a container
    
    Args:
        container_name (str): Name of the container
        blob_name (str): Name of the blob to delete
        
    Returns:
        None
        
    Raises:
        Exception: If there's an error deleting the blob
    """
    try:
        blob_client = blob_service_client.get_blob_client(container=container_name, blob=blob_name)
        blob_client.delete_blob()
        logging.info(f"Successfully deleted blob {blob_name} from container {container_name}")
    except Exception as e:
        logging.error(f"Error deleting blob {blob_name} from container {container_name}: {str(e)}")
        raise

def delete_all_blobs_in_container(container_name):
    """
    Delete all blobs in a container.
    
    Args:
        container_name (str): Name of the container
        
    Returns:
        None
        
    Raises:
        Exception: If there's an error deleting the blobs
    """
    try:
        container_client = blob_service_client.get_container_client(container_name)
        blob_list = container_client.list_blobs()
        for blob in blob_list:
            blob_client = container_client.get_blob_client(blob.name)
            blob_client.delete_blob()
        logging.info(f"Successfully deleted all blobs in container {container_name}")
    except Exception as e:
        logging.error(f"Error deleting all blobs in container {container_name}: {str(e)}")
        raise