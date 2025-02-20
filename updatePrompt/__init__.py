# update_prompt/__init__.py
import logging, json, azure.functions as func
from utils.db import update_prompt_in_db

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Processing update_prompt request.')
    
    try:
        prompt_data = req.get_json()
    except ValueError:
        return func.HttpResponse("Invalid JSON", status_code=400)
    
    try:
        updated_prompt = update_prompt_in_db(prompt_data)
        return func.HttpResponse(
            json.dumps(updated_prompt),
            status_code=200,
            mimetype="application/json"
        )
    except Exception as e:
        logging.error(f"Error updating prompt: {str(e)}")
        return func.HttpResponse("Error updating prompt", status_code=500)
