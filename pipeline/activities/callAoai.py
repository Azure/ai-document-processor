import azure.durable_functions as df

import logging
import os
from utils.prompts import load_prompts
from utils.blob_functions import get_blob_content, write_to_blob
from utils.azure_openai import run_prompt
import json

name = "callAoai"
bp = df.Blueprint()

@bp.function_name(name)
@bp.activity_trigger(input_name="textResult")
def run(textResult: str):
    """
    Calls the Azure OpenAI service with the provided text result.
    
    Args:
        text_result (str): The text result to be processed by the Azure OpenAI service.
    
    Returns:
        str: The response from the Azure OpenAI service.
    """
    try:
      # Load the prompt
      prompt_json = load_prompts()
      
      # Call the Azure OpenAI service
      response_content = run_prompt(prompt_json['system_prompt'], textResult)
      if response_content.startswith('```json') and response_content.endswith('```'):
        response_content = response_content.strip('`')
        response_content = response_content.replace('json', '', 1).strip()
      
      json_str = json.dumps(response_content)
      # Return the response
      return json_str
  
    except Exception as e:
        logging.error(f"Error processing {textResult}: {e}")
        return None