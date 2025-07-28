import os
import json
from pipelineUtils.blob_functions import get_blob_content
import yaml
import logging

from configuration import Configuration
config = Configuration()

def load_prompts_from_blob(prompt_file):
    """Load the prompt from YAML file in blob storage and return as a dictionary."""
    try:
        prompt_yaml = get_blob_content("prompts", prompt_file).decode('utf-8')
        prompts = yaml.safe_load(prompt_yaml)
        prompts_json = json.dumps(prompts, indent=4)
        prompts = json.loads(prompts_json) 
        return prompts
    except Exception as e:
        raise RuntimeError(f"Failed to load prompts file: {prompt_file} from blob storage. Prompt File should be a valid Blob path stored in the prompts container. Error: {e}")
    

def load_prompts_from_blob(prompt_file):
    """Load the prompt from YAML file in blob storage and return as a dictionary."""
    try:
        prompt_yaml = get_blob_content("prompts", prompt_file).decode('utf-8')
        prompts = yaml.safe_load(prompt_yaml)
        prompts_json = json.dumps(prompts, indent=4)
        prompts = json.loads(prompts_json) 
        return prompts
    except Exception as e:
        raise RuntimeError(f"Failed to load prompts from blob storage: {e}")
    

def load_prompts():
    """Fetch prompts JSON from blob storage and return as a dictionary."""
    prompt_file = config.get_value("PROMPT_FILE")
    
    if not prompt_file:
        raise ValueError("Environment variable PROMPT_FILE is not set.")
    
    if prompt_file=="COSMOS":
        prompts = load_prompts_from_cosmos()
    else:
        prompts = load_prompts_from_blob(prompt_file)

    # Validate required fields
    required_keys = ["system_prompt", "user_prompt"]
    for key in required_keys:
        if key not in prompts:
            raise KeyError(f"Missing required prompt key: {key}")

    return prompts