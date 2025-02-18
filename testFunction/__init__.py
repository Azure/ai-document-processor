import azure.functions as func
import logging

def main(req: func.HttpRequest) -> func.HttpResponse:
  logging.info('Python HTTP trigger function processed a request.')
  
  #Parse arbitrary request
  req_body = req.get_json()
  logging.info(f"req_body: {req_body}")

  return func.HttpResponse(
    "This HTTP triggered function executed successfully. Pass a name in the query string or in the request body for a personalized response.",
    status_code=200
  )