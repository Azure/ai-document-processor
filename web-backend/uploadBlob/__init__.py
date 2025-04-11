import logging
import azure.functions as func
import json
import base64
from backendUtils.blob_functions import write_to_blob

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("Python HTTP trigger function processed a request for uploadBlob.")
    
    try:
        # Parse request body
        req_body = req.get_json()
        
        # Validate required fields
        if not req_body or 'container' not in req_body or 'filename' not in req_body or 'fileContent' not in req_body:
            return func.HttpResponse(
                "Request body must contain 'container', 'filename', and 'fileContent' fields",
                status_code=400
            )
        
        container_name = req_body['container']
        filename = req_body['filename']
        file_content_base64 = req_body['fileContent']
        
        # Validate container name
        valid_containers = ['bronze', 'silver', 'gold']
        if container_name not in valid_containers:
            return func.HttpResponse(
                f"Container name must be one of: {', '.join(valid_containers)}",
                status_code=400
            )
        
        # Decode base64 content
        try:
            file_content = base64.b64decode(file_content_base64)
        except Exception as e:
            return func.HttpResponse(
                f"Error decoding file content: {str(e)}",
                status_code=400
            )
        
        # Upload to blob storage using the utility function
        write_to_blob(container_name, filename, file_content)
        
        # Return success response with blob details
        result = {
            "success": True,
            "container": container_name,
            "filename": filename,
            "sizeBytes": len(file_content)
        }
        
        return func.HttpResponse(
            json.dumps(result),
            mimetype="application/json",
            status_code=200
        )
        
    except Exception as e:
        logging.error(f"Error in uploadBlob: {str(e)}")
        return func.HttpResponse(
            f"Error uploading file: {str(e)}",
            status_code=500
        )
