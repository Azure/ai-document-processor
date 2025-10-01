# backendUtils/db.py
import os
import logging
import json
from azure.cosmos import CosmosClient, PartitionKey, exceptions
from azure.identity import DefaultAzureCredential
from datetime import datetime
import uuid
# Set up logging
logging.basicConfig(level=logging.INFO)

from configuration import Configuration
config = Configuration()

# Retrieve Cosmos DB settings from environment variables
COSMOS_DB_URI = config.get_value("COSMOS_DB_URI")
COSMOS_DB_DATABASE = config.get_value("COSMOS_DB_DATABASE_NAME")
COSMOS_DB_CONVERSATION_CONTAINER = config.get_value("COSMOS_DB_CONVERSATION_HISTORY_CONTAINER")


def save_chat_message(conversation_id: str, role: str, content: str, usage: dict = None):
    client = CosmosClient(COSMOS_DB_URI, credential=config.credential)
    db = client.get_database_client(COSMOS_DB_DATABASE)
    container = db.get_container_client(COSMOS_DB_CONVERSATION_CONTAINER)

    item = {
        "id": str(uuid.uuid4()),
        "conversationId": conversation_id,
        "role": role,
        "content": content,
        "timestamp": datetime.utcnow().isoformat() + "Z"
    }
    if usage:
        item.update({
            "promptTokens": usage.get("prompt_tokens"),
            "completionTokens": usage.get("completion_tokens"),
            "totalTokens": usage.get("total_tokens"),
            "model": usage.get("model")
        })

    return container.create_item(body=item)