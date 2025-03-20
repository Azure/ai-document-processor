# delete_prompt/__init__.py
import logging, azure.functions as func
from utils.db import delete_prompt_from_db

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Processing delete_prompt request.')
    prompt_id = req.params.get('id')
    if not prompt_id:
        return func.HttpResponse("Missing id parameter", status_code=400)
    
    try:
        delete_prompt_from_db(prompt_id)
        return func.HttpResponse("Prompt deleted successfully", status_code=200)
    except Exception as e:
        logging.error(f"Error deleting prompt: {str(e)}")
        return func.HttpResponse("Error deleting prompt", status_code=500)
