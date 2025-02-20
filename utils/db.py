# utils/db.py
import os
import logging
import json
from azure.cosmos import CosmosClient, PartitionKey, exceptions
from azure.identity import DefaultAzureCredential

# Set up logging
logging.basicConfig(level=logging.INFO)

# Retrieve Cosmos DB settings from environment variables
COSMOS_DB_URI = os.environ.get("COSMOS_DB_URI")
COSMOS_DB_DATABASE = os.environ.get("COSMOS_DB_DATABASE")
COSMOS_DB_PROMPTS_CONTAINER = os.environ.get("COSMOS_DB_PROMPTS_CONTAINER")
COSMOS_DB_CONFIG_CONTAINER = os.environ.get("COSMOS_DB_CONFIG_CONTAINER")

# Initialize Cosmos DB client using Managed Identity credentials
# DefaultAzureCredential will use the managed identity assigned to your Function App.
credential = DefaultAzureCredential()
client = CosmosClient(COSMOS_DB_URI, credential=credential)
database = client.get_database_client(COSMOS_DB_DATABASE)
prompts_container = database.get_container_client(COSMOS_DB_PROMPTS_CONTAINER)
config_container = database.get_container_client(COSMOS_DB_CONFIG_CONTAINER)


def get_all_prompts():
    """
    Retrieve all prompt documents from the prompts container.
    """
    try:
        query = "SELECT * FROM c"
        items = list(prompts_container.query_items(
            query=query,
            enable_cross_partition_query=True
        ))
        return items
    except exceptions.CosmosHttpResponseError as e:
        logging.error(f"Error retrieving prompts: {str(e)}")
        return []


def get_live_prompt_id():
    """
    Retrieve the live prompt ID from the configuration container.
    Assumes a document with id 'live_prompt_config' exists.
    """
    try:
        config_item = config_container.read_item(
            item="live_prompt_config",
            partition_key="live_prompt_config"
        )
        return config_item.get("prompt_id")
    except exceptions.CosmosHttpResponseError as e:
        logging.error(f"Error retrieving live prompt config: {str(e)}")
        return None


def add_prompt_to_db(prompt_data: dict):
    """
    Create a new prompt document in the prompts container.
    Assumes the document's 'id' is either provided or generated.
    """
    try:
        created_item = prompts_container.create_item(body=prompt_data)
        logging.info(f"Prompt created with id: {created_item['id']}")
        return created_item
    except exceptions.CosmosHttpResponseError as e:
        logging.error(f"Error creating prompt: {str(e)}")
        return None


def update_prompt_in_db(prompt_data: dict):
    """
    Update a prompt document in the prompts container.
    Assumes the document's 'id' is present in prompt_data and that
    the partition key is the same as the prompt's id.
    """
    try:
        # Read the existing item first (optional, but useful for etag handling)
        existing_item = prompts_container.read_item(
            item=prompt_data['id'],
            partition_key=prompt_data['id']
        )
        # Replace the item with the updated data
        updated_item = prompts_container.replace_item(
            item=existing_item,
            body=prompt_data
        )
        logging.info(f"Prompt updated: {prompt_data['id']}")
        return updated_item
    except exceptions.CosmosHttpResponseError as e:
        logging.error(f"Error updating prompt {prompt_data.get('id')}: {str(e)}")
        return None


def delete_prompt_from_db(prompt_id: str):
    """
    Delete a prompt document from the prompts container.
    Assumes the partition key is the prompt id.
    """
    try:
        prompts_container.delete_item(
            item=prompt_id,
            partition_key=prompt_id
        )
        logging.info(f"Prompt deleted: {prompt_id}")
    except exceptions.CosmosHttpResponseError as e:
        logging.error(f"Error deleting prompt {prompt_id}: {str(e)}")
        raise


def set_live_prompt(prompt_id: str):
    """
    Update the configuration document in the config container to set the live prompt.
    Assumes a configuration document with id 'live_prompt_config' exists.
    """
    try:
        config_item = config_container.read_item(
            item="live_prompt_config",
            partition_key="live_prompt_config"
        )
        config_item["prompt_id"] = prompt_id
        updated_config = config_container.replace_item(
            item="live_prompt_config",
            body=config_item
        )
        logging.info(f"Live prompt set to: {prompt_id}")
        return updated_config
    except exceptions.CosmosHttpResponseError as e:
        logging.error(f"Error setting live prompt to {prompt_id}: {str(e)}")
        return None
