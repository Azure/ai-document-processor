import azure.functions as func
import azure.durable_functions as df
from azure.durable_functions import RetryOptions


from activities import runDocIntel, callAiFoundry, writeToBlob, speechToText, callFoundryMultiModal
from configuration import Configuration

from pipelineUtils.blob_functions import BlobMetadata

config = Configuration()

# NEXT_STAGE = config.get_value("NEXT_STAGE")
FINAL_OUTPUT_CONTAINER = config.get_value("FINAL_OUTPUT_CONTAINER")

app = df.DFApp(http_auth_level=func.AuthLevel.FUNCTION)

import logging

# # Blob-triggered starter
@app.function_name(name="start_orchestrator_on_blob")
@app.blob_trigger(
    arg_name="blob",
    path="bronze/{name}",
    connection="DataStorage",
    source="EventGrid",
)
@app.durable_client_input(client_name="client")
async def start_orchestrator_blob(
    blob: func.InputStream,
    client: df.DurableOrchestrationClient,
):
    logging.info(f" Blob Trigger (start_orchestrator_blob) - Blob Received: {blob}") 
    logging.info(f"path: {blob.name}")
    logging.info(f"Size: {blob.length} bytes")
    logging.info(f"URI: {blob.uri}")   

    blob_metadata = BlobMetadata(
        name=blob.name,
        container="bronze",
        uri=blob.uri
    )
    logging.info(f"Blob Metadata: {blob_metadata}")
    logging.info(f"Blob Metadata JSON: {blob_metadata.to_dict()}")
    instance_id = await client.start_new("process_blob", client_input=blob_metadata.to_dict())
    logging.info(f"Started orchestration {instance_id} for blob {blob.name}")


# An HTTP-triggered function with a Durable Functions client binding
@app.route(route="client")
@app.durable_client_input(client_name="client")
async def start_orchestrator_http(req: func.HttpRequest, client):
    """
    Starts a new orchestration instance and returns a response to the client.

    args:
        req (func.HttpRequest): The HTTP request object. Contains an array of JSONs with fields: name, and container
        client (DurableOrchestrationClient): The Durable Functions client.
    response:
        func.HttpResponse: The HTTP response object.
    """
    
    #Perform basic validation on the request body
    try:
        body = req.get_json()
        blob_name = body.get("name")
        blob_uri = body.get("uri")

    except ValueError:
        return func.HttpResponse("Invalid JSON.", status_code=400)

   
    blob_input = {
        "name": blob_name,
        "container": "bronze",
        "uri": blob_uri
    }

    #invoke the process_blob function with the list of blobs
    instance_id = await client.start_new('process_blob', client_input=blob_input)
    logging.info(f"Started orchestration with Batch ID = '{instance_id}'.")

    response = client.create_check_status_response(req, instance_id)
    return response


#Sub orchestrator
@app.function_name(name="process_blob")
@app.orchestration_trigger(context_name="context")
def process_blob(context):
    blob_input = context.get_input()
    sub_orchestration_id = context.instance_id 
    logging.info(f"Process Blob sub Orchestration - Processing blob_metadata: {blob_input} with sub orchestration id: {sub_orchestration_id}")
    # Get file extensions
    blob_name = blob_input.get("name", "")
    file_extension = blob_name.lower().split('.')[-1] if '.' in blob_name else ""
    # Audio file extensions
    audio_extensions = ['wav', 'mp3', 'opus', 'ogg', 'flac', 'wma', 'aac', 'webm']
    # Document file extensions
    document_extensions = ['pdf', 'docx', 'doc', 'xlsx', 'pptx', 'jpg', 'jpeg', 'png', 'tiff', 'bmp']
    

    # Define retry options for handling transient failures
    # Note: backoff_coefficient requires azure-functions-durable >= 1.3.0
    retry_options = RetryOptions(
        first_retry_interval_in_milliseconds=5000,    # 5 seconds initial wait
        max_number_of_attempts=5                       # More attempts for rate limit scenarios
    )

    # 1. Process Data Source based on file type
    if config.get_value("AOAI_MULTI_MODAL", "false").lower() == "true" and file_extension in document_extensions:
        aoai_input = {
            "name": blob_input.get("name"),
            "container": blob_input.get("container"),
            "uri": blob_input.get("uri"),
            "instance_id": sub_orchestration_id
        }

        text_result = yield context.call_activity_with_retry("callAoaiMultiModal", retry_options, aoai_input)


    elif config.get_value("AI_VISION_ENABLED", "false").lower() == "true":
        pass

    elif file_extension in audio_extensions:
        # Process audio with speech-to-text
        logging.info(f"Processing audio file: {blob_name}")
        text_result = yield context.call_activity_with_retry("speechToText", retry_options, blob_input)

    elif file_extension in document_extensions:
        # Process document with Document Intelligence
        logging.info(f"Processing document file: {blob_name}")
        text_result = yield context.call_activity_with_retry("runDocIntel", retry_options, blob_input)
        
    else:
        # Unsupported file type
        logging.warning(f"Unsupported file type: {file_extension} for blob: {blob_name}")
        return {
            "blob": blob_input,
            "error": f"Unsupported file type: {file_extension}",
            "status": "skipped"
        }
    
    # 2. Feed Output into AOAI to get insights
    # Package the data into a dictionary
    call_aoai_input = {
        "text_result": text_result,
        "instance_id": sub_orchestration_id 
    }

    aoai_output = yield context.call_activity_with_retry("callAoai", retry_options, call_aoai_input)
    

    # 3. Write AOAI output to Blob Storage
    task_result = yield context.call_activity_with_retry(
        "writeToBlob", 
        retry_options,
        {
            "json_str": aoai_output, 
            "blob_name": blob_input["name"],
            "final_output_container": FINAL_OUTPUT_CONTAINER
        }
    )
    return {
        "blob": blob_input,
        "text_result": aoai_output,
        "task_result": task_result
    }   

app.register_functions(runDocIntel.bp)
app.register_functions(callAiFoundry.bp)
app.register_functions(writeToBlob.bp)
app.register_functions(speechToText.bp)
app.register_functions(callFoundryMultiModal.bp)