# create_prompt/__init__.py
import logging
import json
import azure.functions as func
from utils.db import add_prompt_to_db

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Processing create_prompt request.")

    try:
      prompt_data = req.get_json()
    except ValueError:
      return func.HttpResponse("Invalid JSON", status_code=400)

    created_prompt = add_prompt_to_db(prompt_data)
    if created_prompt:
        return func.HttpResponse(
          json.dumps(created_prompt),
          status_code=201,
          mimetype="application/json"
        )
    else:
        return func.HttpResponse("Error creating prompt", status_code=500)
