# backendUtils/db.py
import os
import logging
import json
from azure.cosmos import CosmosClient, PartitionKey, exceptions
from azure.identity import DefaultAzureCredential

# Set up logging
logging.basicConfig(level=logging.INFO)

from configuration import Configuration
config = Configuration()

# Retrieve Cosmos DB settings from environment variables
COSMOS_DB_URI = config.get_value("COSMOS_DB_URI")
COSMOS_DB_DATABASE = config.get_value("COSMOS_DB_PROMPTS_DB")
COSMOS_DB_PROMPTS_CONTAINER = config.get_value("COSMOS_DB_PROMPTS_CONTAINER")
COSMOS_DB_CONFIG_CONTAINER = config.get_value("COSMOS_DB_CONFIG_CONTAINER")

# Initialize Cosmos DB client using Managed Identity credentials
# DefaultAzureCredential will use the managed identity assigned to your Function App.

def get_prompt_by_id(prompt_id: str):
    """
    Retrieve a prompt document by its ID from the prompts container.
    """
    client = CosmosClient(COSMOS_DB_URI, credential=config.credential)
    database = client.get_database_client(COSMOS_DB_DATABASE)
    prompts_container = database.get_container_client(COSMOS_DB_PROMPTS_CONTAINER)
    
    try:
        item = prompts_container.read_item(
            item=prompt_id,
            partition_key=prompt_id
        )

        return item
    
    except exceptions.CosmosHttpResponseError as e:
        logging.error(f"Error retrieving prompt {prompt_id}: {str(e)}")
        return None



def get_live_prompt_id():
    """
    Retrieve the live prompt ID from the configuration container.
    Assumes a document with id 'live_prompt_config' exists.
    """
    client = CosmosClient(COSMOS_DB_URI, credential=config.credential)
    database = client.get_database_client(COSMOS_DB_DATABASE)
    config_container = database.get_container_client(COSMOS_DB_CONFIG_CONTAINER)
    
    try:
        config_item = config_container.read_item(
            item="live_prompt_config",
            partition_key="live_prompt_config"
        )
        return config_item.get("prompt_id")
    except Exception as e:
        logging.error(f"Error retrieving live prompt config: {str(e)}")
        return None