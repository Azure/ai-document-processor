import logging
import os
from utils.prompts import load_prompts


def get_prompts_from_yaml():
 
  try:
    prompts = load_prompts()  # Ensure prompts are loaded
    logging.info(f"Prompts loaded successfully \n {prompts}")
    # prompts = yaml.safe_load(blob_content)
    prompts_json = json.dumps(prompts, indent=4)

    # Return JSON response
    return func.HttpResponse(prompts_json, mimetype="application/json")

  except Exception as e:
    logging.error(f"Error fetching prompts: {str(e)}")
    return func.HttpResponse(f"Error: {str(e)}", status_code=500)