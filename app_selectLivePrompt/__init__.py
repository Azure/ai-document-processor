# select_live_prompt/__init__.py
import logging, json, azure.functions as func
from utils.db import set_live_prompt

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Processing select_live_prompt request.')
    
    try:
        data = req.get_json()
        prompt_id = data.get('id')
        if not prompt_id:
            return func.HttpResponse("Missing prompt id", status_code=400)
    except ValueError:
        return func.HttpResponse("Invalid JSON", status_code=400)
    
    try:
        set_live_prompt(prompt_id)
        return func.HttpResponse("Live prompt updated successfully", status_code=200)
    except Exception as e:
        logging.error(f"Error updating live prompt: {str(e)}")
        return func.HttpResponse("Error updating live prompt", status_code=500)
