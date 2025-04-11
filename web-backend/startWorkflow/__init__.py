# update_prompt/__init__.py
import logging, json, azure.functions as func
import requests
import os

def main(req: func.HttpRequest) -> func.HttpResponse:
    """
    This function is a proxy for the client durable function.
    It forwards the request to the client durable function and returns the response.
    args:
        req (func.HttpRequest): The HTTP request object.\
        '{
            "blobs": [
                {
                    "name": full blob path,
                    "url": full url with SAS token,
                    "container": container name
                }
            ]
        }'
    returns:
        func.HttpResponse: The HTTP response object.
    """
    # Extract the request body
    try:
        body = req.get_json()
    except ValueError:
        return func.HttpResponse(
            "Invalid request body",
            status_code=400
        )
    
    PROCESSING_FUNCTION_APP_NAME = os.getenv('PROCESSING_FUNCTION_APP_NAME')
    # URL of the client durable function
    durable_function_url = f"https://{PROCESSING_FUNCTION_APP_NAME}.azurewebsites.net/api/orchestrators/orchestrator"

    # Forward the request to the durable function
    try:
        response = requests.post(durable_function_url, json=body)
        response.raise_for_status()
    
    except requests.exceptions.RequestException as e:
        logging.error(f"Error calling durable function: {e}")
        return func.HttpResponse(
            json.dumps({"error": f"Error calling durable function: {e}"}),
            status_code=500,
            mimetype="application/json"
        )

    # Return the response from the durable function
    return func.HttpResponse(
        response.content,
        status_code=response.status_code,
        mimetype=response.headers.get('Content-Type')
    )