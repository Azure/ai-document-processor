import azure.durable_functions as df

import logging
import os
from pipelineUtils.prompts import load_prompts
from pipelineUtils.blob_functions import get_blob_content, write_to_blob
from pipelineUtils.azure_openai import run_prompt
import json

name = "callAoai"
bp = df.Blueprint()

@bp.function_name(name)
@bp.activity_trigger(input_name="inputData")
def run(inputData: dict):
    """
    Calls the Azure OpenAI service with the provided text result.
    
    Args:
        text_result (str): The text result to be processed by the Azure OpenAI service.
    
    Returns:
        str: The response from the Azure OpenAI service.
    """
    try:
      # Load the prompt
      text_result = inputData.get('text_result')
      instance_id = inputData.get('instance_id')
      
      prompt_json = load_prompts()
      
      full_user_prompt = prompt_json['user_prompt'] + "\n\n" + text_result
      # Call the Azure OpenAI service
      logging.info(f"callAoai.py: Full user prompt: {full_user_prompt}")
      response_content = run_prompt(instance_id, prompt_json['system_prompt'], full_user_prompt)
      if response_content.startswith('```json') and response_content.endswith('```'):
        response_content = response_content.strip('`')
        response_content = response_content.replace('json', '', 1).strip()
      
      json_str = response_content
      # Return the response
      return json_str
  
    except Exception as e:
        logging.error(f"Error processing Sub Orchestration (callAoai): {instance_id}: {e}")
        return None