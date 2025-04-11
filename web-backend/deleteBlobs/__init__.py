import os
import json
import azure.functions as func
from backendUtils.blob_functions import delete_blob
import logging

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Python HTTP trigger function processed a request for deleteBlobs.")
    
    try:
        # Parse the request body
        req_body = req.get_json()
        
        # Check if blobs array exists in the request
        if not req_body or 'blobs' not in req_body:
            return func.HttpResponse(
                "Request body must contain a 'blobs' array",
                status_code=400
            )
        
        blobs = req_body['blobs']
        
        # Delete each blob
        for blob in blobs:
            delete_blob(blob['container'], blob['name'])
        
        return func.HttpResponse(
            json.dumps({"message": "Blobs deleted successfully"}),
            mimetype="application/json",
            status_code=200
        )
        
    except Exception as e:
        return func.HttpResponse(
            json.dumps({"error": str(e)}),
            mimetype="application/json",
            status_code=500
        ) 