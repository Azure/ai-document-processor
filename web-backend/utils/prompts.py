import os
import json
from utils.blob_functions import get_blob_content
import yaml


def load_prompts_from_cosmos():
    """Fetch prompts from Cosmos DB and return as a dictionary."""
    # Placeholder for Cosmos DB fetching logic
    # Replace with actual implementation
    return {
        "system_prompt": "Default system prompt from Cosmos",
        "user_prompt": "Default user prompt from Cosmos"
    }

def load_prompts():
    """Fetch prompts JSON from blob storage and return as a dictionary."""
    prompt_file = os.getenv("PROMPT_FILE")
    
    if not prompt_file:
        raise ValueError("Environment variable PROMPT_FILE is not set.")
    
    if prompt_file=="COSMOS":
        return load_prompts_from_cosmos()

    try:
        prompt_yaml = get_blob_content("prompts", prompt_file).decode('utf-8')
        prompts = yaml.safe_load(prompt_yaml)
        prompts_json = json.dumps(prompts, indent=4)
        prompts = json.loads(prompts_json)  # Ensure it's valid JSON
    except Exception as e:
        raise RuntimeError(f"Failed to load prompts from blob storage: {e}")

    # Validate required fields
    required_keys = ["system_prompt", "user_prompt"]
    for key in required_keys:
        if key not in prompts:
            raise KeyError(f"Missing required prompt key: {key}")

    return prompts