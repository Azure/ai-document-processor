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
        url=blob.uri,            # full blob URL
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
    req (func.HttpRequest): The HTTP request object. Contains an array of JSONs with fields: name, url, and container
    client (DurableOrchestrationClient): The Durable Functions client.
  response:
    func.HttpResponse: The HTTP response object.
  """
  
  #Perform basic validation on the request body
  try:
      body = req.get_json()
  except ValueError:
      return func.HttpResponse("Invalid JSON.", status_code=400)

  blobs = body.get("blobs")
  if not isinstance(blobs, list) or not blobs:
      return func.HttpResponse("Invalid request: 'blobs' must be a non-empty array.", status_code=400)

  required = ("name", "url", "container")
  for i, b in enumerate(blobs):
      if not isinstance(b, dict):
          return func.HttpResponse(f"Invalid request: blobs[{i}] must be an object.", status_code=400)
      if any(k not in b or not isinstance(b[k], str) or not b[k].strip() for k in required):
          return func.HttpResponse(f"Invalid request: blobs[{i}] must contain non-empty string keys {required}.", status_code=400)
  
  #invoke the orchestrator function with the list of blobs
  instance_id = await client.start_new('orchestrator', client_input=blobs)
  logging.info(f"Started orchestration with Batch ID = '{instance_id}'.")

  response = client.create_check_status_response(req, instance_id)
  return response

# Orchestrator
@app.function_name(name="orchestrator")
@app.orchestration_trigger(context_name="context")
def run(context):
  input_data = context.get_input()
  logging.info(f"Context {context}")
  logging.info(f"Input data: {input_data}")
  
  sub_tasks = []

  for blob_metadata in input_data:
    logging.info(f"Calling sub orchestrator for blob: {blob_metadata}")
    sub_tasks.append(context.call_sub_orchestrator("ProcessBlob", blob_metadata))

  logging.info(f"Sub tasks: {sub_tasks}")

  # Runs a list of asynchronous tasks in parallel and waits for all of them to complete. In this case, the tasks are sub-orchestrations that process each blob_metadata in parallel
  results = yield context.task_all(sub_tasks)
  logging.info(f"Results: {results}")
  return results

#Sub orchestrator
@app.function_name(name="ProcessBlob")
@app.orchestration_trigger(context_name="context")
def process_blob(context):
  blob_metadata = context.get_input()
  sub_orchestration_id = context.instance_id 
  logging.info(f"Process Blob sub Orchestration - Processing blob_metadata: {blob_metadata} with sub orchestration id: {sub_orchestration_id}")
  # Waits for the result of an activity function that retrieves the blob_metadata content
  text_result = yield context.call_activity("runDocIntel", blob_metadata)

  # Package the data into a dictionary
  call_aoai_input = {
      "text_result": text_result,
      "instance_id": sub_orchestration_id 
  }

  json_str = yield context.call_activity("callAoai", call_aoai_input)
  
  task_result = yield context.call_activity(
      "writeToBlob", 
      {
          "json_str": json_str, 
          "blob_name": blob_metadata["name"]
      }
  )
  return {
      "blob": blob_metadata,
      "text_result": text_result,
      "task_result": task_result
  }   

app.register_functions(getBlobContent.bp)
app.register_functions(runDocIntel.bp)
app.register_functions(callAoai.bp)
app.register_functions(writeToBlob.bp)