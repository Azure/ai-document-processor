import os
import logging
import json
from azure.cosmos import CosmosClient, PartitionKey, exceptions
from azure.identity import DefaultAzureCredential
import uuid
# Set up logging
logging.basicConfig(level=logging.INFO)

# Retrieve Cosmos DB settings from environment variables
COSMOS_DB_URI = os.environ.get("COSMOS_DB_URI").strip('"')
COSMOS_DB_DATABASE = os.environ.get("COSMOS_DB_PROMPTS_DB").strip('"')
COSMOS_DB_PROMPTS_CONTAINER = os.environ.get("COSMOS_DB_PROMPTS_CONTAINER").strip('"')
COSMOS_DB_CONFIG_CONTAINER = os.environ.get("COSMOS_DB_CONFIG_CONTAINER").strip('"')

print(COSMOS_DB_URI)
print(COSMOS_DB_DATABASE)
print(COSMOS_DB_CONFIG_CONTAINER)
# Initialize Cosmos DB client using Managed Identity credentials
# DefaultAzureCredential will use the managed identity assigned to your Function App.
credential = DefaultAzureCredential()
client = CosmosClient(COSMOS_DB_URI, credential=credential)
database = client.get_database_client(COSMOS_DB_DATABASE)
prompts_container = database.get_container_client(COSMOS_DB_PROMPTS_CONTAINER)
config_container = database.get_container_client(COSMOS_DB_CONFIG_CONTAINER)


def add_prompt_to_db(config_data: dict):
    """
    Create a new prompt document in the prompts container.
    Assumes the document's 'id' is either provided or generated.
    """
    try:
      created_item = config_container.create_item(body=config_data)
      logging.info(f"Prompt created with id: {created_item['id']}")
      return created_item
    except exceptions.CosmosHttpResponseError as e:
      logging.error(f"Error creating prompt: {str(e)}")
      return None

if __name__ == "__main__":
    # Example usage
    config_data = {
      "id": "live_prompt_config",
      "prompt_id": str(uuid.uuid4())
    }
    response = add_prompt_to_db(config_data)
    print(response)