import os
from azure.cosmos import CosmosClient, PartitionKey

def load_prompts_from_cosmos():
    """
    Reads prompts from Cosmos DB and returns them.
    """
    # Example: Read Cosmos DB credentials from environment variables
    cosmos_url = os.getenv("COSMOS_URL")
    cosmos_key = os.getenv("COSMOS_KEY")
    cosmos_database = os.getenv("COSMOS_DATABASE")
    cosmos_container = os.getenv("COSMOS_CONTAINER")

    client = CosmosClient(cosmos_url, credential=cosmos_key)
    database = client.get_database_client(cosmos_database)
    container = database.get_container_client(cosmos_container)

    # Query example
    query = "SELECT * FROM c"
    items = list(container.query_items(query=query, enable_cross_partition_query=True))

    # Return the items or format them as needed
    return items
