import azure.functions as func
import logging
import os
from utils.prompts import load_prompts
from utils.blob_functions import get_blob_content, write_to_blob
from utils.azure_openai import run_prompt
import json

def main(req: func.HttpRequest) -> func.HttpResponse:
    logging.info('Python HTTP trigger function processed a request.')
    try:
        req_body = req.get_json()
        # Get the list of blobs sent from the frontend (if any)
        selected_blobs = req_body.get("blobs", None)
        
        if not selected_blobs:
            return func.HttpResponse(
                json.dumps({"error": "No blobs provided."}),
                status_code=400,
                mimetype="application/json"
            )
        
        processed_files = []
        errors = []
        
        # Loop through each blob provided
        for blob in selected_blobs:
            blob_name = blob.get("name")
            container_name = blob.get("container", "silver")  # Default to 'silver' if not provided
            
            if not blob_name:
                errors.append("Blob is missing the 'name' property.")
                continue
            
            # Disallow processing if the blob comes from a disallowed container
            if container_name == "bronze":
                logging.warning(f"Skipping blob from the bronze container: {blob_name}")
                errors.append(f"Processing blobs from the 'bronze' container is not allowed: {blob_name}")
                continue
            
            logging.info(f"Processing blob: {blob_name} from container: {container_name}")
            
            # Step 1: Get the content of the specified blob (expects a .txt file)
            try:
                content = get_blob_content(container_name, blob_name).decode('utf-8')
            except Exception as e:
                error_msg = f"Error getting content for blob {blob_name}: {str(e)}"
                logging.error(error_msg)
                errors.append(error_msg)
                continue
            
            logging.info(f"Blob content: {content}")
            
            # Step 2: Load Prompts
            try:
                logging.info("Loading Prompts")
                prompts = load_prompts()
                system_prompt = prompts["system_prompt"]
                user_prompt = prompts["user_prompt"]
            except Exception as e:
                error_msg = f"Error loading prompts for blob {blob_name}: {str(e)}"
                logging.error(error_msg)
                errors.append(error_msg)
                continue
            
            full_user_prompt = user_prompt + content
            
            # Step 3: Call OpenAI to generate response
            try:
                response_content = run_prompt(system_prompt, full_user_prompt)
            except Exception as e:
                error_msg = f"Error running prompt for blob {blob_name}: {str(e)}"
                logging.error(error_msg)
                errors.append(error_msg)
                continue
            
            # Clean up JSON response if necessary
            if response_content.startswith('```json') and response_content.endswith('```'):
                response_content = response_content.strip('`')
                response_content = response_content.replace('json', '', 1).strip()
            
            json_bytes = response_content.encode('utf-8')
            
            # Step 4: Write the response to a blob in the 'gold' container
            try:
                sourcefile = os.path.splitext(os.path.basename(blob_name))[0]
                write_to_blob("gold", f"{sourcefile}-output.json", json_bytes)
                processed_files.append(blob_name)
            except Exception as e:
                error_msg = f"Error writing output for blob {blob_name}: {str(e)}"
                logging.error(error_msg)
                errors.append(error_msg)
                continue
        
        # Prepare the response payload
        response_data = {
            "processedFiles": processed_files,
            "errors": errors,
            "status": "completed" if not errors else "completed_with_errors"
        }
        
        status_code = 200 if not errors else 500
        
        return func.HttpResponse(
            json.dumps(response_data),
            status_code=status_code,
            mimetype="application/json"
        )
    
    except Exception as e:
        logging.error(f"Error: {str(e)}")
        return func.HttpResponse(
            json.dumps({"error": str(e)}),
            status_code=500,
            mimetype="application/json"
        )