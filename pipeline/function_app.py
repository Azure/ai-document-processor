import azure.functions as func
import azure.durable_functions as df

from azure.ai.documentintelligence import DocumentIntelligenceClient
from azure.ai.documentintelligence.models import AnalyzeResult, AnalyzeDocumentRequest

from activities import getBlobContent, runDocIntel, callAoai, writeToBlob
from configuration import Configuration

from pipelineUtils.prompts import load_prompts
from pipelineUtils.blob_functions import get_blob_content, write_to_blob, BlobMetadata
from pipelineUtils.azure_openai import run_prompt

config = Configuration()

NEXT_STAGE = config.get_value("NEXT_STAGE")

app = df.DFApp(http_auth_level=func.AuthLevel.ANONYMOUS)

import logging

# Blob-triggered starter
@app.function_name(name="start_orchestrator_on_blob")
@app.blob_trigger(
    arg_name="blob",
    path="bronze/{name}",
    connection="DataStorage",
)
@app.durable_client_input(client_name="client")
async def start_orchestrator_blob(
    blob: func.InputStream,
    client: df.DurableOrchestrationClient,
):
    logging.info(f"Blob Received: {blob}") 
    logging.info(f"path: {blob.name}")
    logging.info(f"Size: {blob.length} bytes")
    logging.info(f"URI: {blob.uri}")   

    blob_metadata = BlobMetadata(
        name=blob.name,          # e.g. 'bronze/file.txt'
        container="bronze",
    )
    logging.info(f"Blob Metadata: {blob_metadata}")
    logging.info(f"Blob Metadata JSON: {blob_metadata.to_dict()}")
    instance_id = await client.start_new("orchestrator", client_input=[blob_metadata.to_dict()])
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

    except ValueError:
        return func.HttpResponse("Invalid JSON.", status_code=400)

   
    blob_input = {
        "name": blob_name,
        "container": "bronze"
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
    # Waits for the result of an activity function that retrieves the blob_input content
    doc_intel_output = yield context.call_activity("runDocIntel", blob_input)

    # Package the data into a dictionary
    call_aoai_input = {
        "text_result": doc_intel_output,
        "instance_id": sub_orchestration_id 
    }

    aoai_output = yield context.call_activity("callAoai", call_aoai_input)
    
    task_result = yield context.call_activity(
        "writeToBlob", 
        {
            "json_str": aoai_output, 
            "blob_name": blob_input["name"]
        }
    )
    return {
        "blob": blob_input,
        "text_result": aoai_output,
        "task_result": task_result
    }   

app.register_functions(getBlobContent.bp)
app.register_functions(runDocIntel.bp)
app.register_functions(callAoai.bp)
app.register_functions(writeToBlob.bp)