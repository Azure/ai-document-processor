# list_prompts/__init__.py
import logging
import azure.functions as func
from utils.db import get_all_prompts, get_live_prompt_id
import json

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Processing list_prompts request.')

    try:
        logging.info('Fetching all prompts and live prompt ID.')
        prompts = get_all_prompts()  # Returns a list of prompt dicts
        logging.info(f"Retrieved {len(prompts)} prompts.")

        logging.info('Fetching live prompt ID.')
        live_prompt_id = get_live_prompt_id()  # Returns the id of the live prompt
        logging.info(f"Live prompt ID: {live_prompt_id}")
        
        response = {
            "prompts": prompts,
            "livePromptId": live_prompt_id
        }
        return func.HttpResponse(
            body=json.dumps(response),
            status_code=200,
            mimetype="application/json"
        )
    except Exception as e:
        logging.error(f"Error listing prompts: {str(e)}")
        return func.HttpResponse("Error retrieving prompts", status_code=500)