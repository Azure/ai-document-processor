import azure.functions as func
import azure.durable_functions as df

from azure.ai.documentintelligence import DocumentIntelligenceClient
from azure.ai.documentintelligence.models import AnalyzeResult, AnalyzeDocumentRequest

from activities import getBlobContent, runDocIntel, callAoai, writeToBlob
from configuration import Configuration

from pipelineUtils.prompts import load_prompts
from pipelineUtils.blob_functions import get_blob_content, write_to_blob
from pipelineUtils.azure_openai import run_prompt

config = Configuration()

NEXT_STAGE = config.get_value("NEXT_STAGE")

app = df.DFApp(http_auth_level=func.AuthLevel.ANONYMOUS)

import logging

@app.function_name(name="ai_doc_blob_trigger")
@app.blob_trigger(arg_name="req", path=f'{config.get_value("AI_DOC_PROC_CONTAINER_NAME","bronze")}/{{name}}', connection=config.get_value("AI_DOC_PROC_CONNECTION_NAME","AzureWebJobsStorage"), data_type=func.DataType.BINARY)
def ai_doc_blob_trigger(req:func.InputStream):
    
    source_container = config.get_value("AI_DOC_PROC_CONTAINER_NAME", "bronze")
    endpoint = config.get_value("AIMULTISERVICES_ENDPOINT")
    try:
      client = DocumentIntelligenceClient(
          endpoint=endpoint, credential=config.credential
      )

      poller = client.begin_analyze_document(
          # AnalyzeDocumentRequest Class: https://learn.microsoft.com/en-us/python/api/azure-ai-documentintelligence/azure.ai.documentintelligence.models.analyzedocumentrequest?view=azure-python
          "prebuilt-read", AnalyzeDocumentRequest(bytes_source=req.read())
        )
      
      result: AnalyzeResult = poller.result()
      
      if result.paragraphs:    
          paragraphs = "\n".join([paragraph.content for paragraph in result.paragraphs])            
      
      try:
        # Load the prompt
        prompt_json = load_prompts()
        
        # Call the Azure OpenAI service
        response_content = run_prompt(paragraphs, prompt_json['system_prompt'])
        if response_content.startswith('```json') and response_content.endswith('```'):
          response_content = response_content.strip('`')
          response_content = response_content.replace('json', '', 1).strip()

        #remove the container name from start of the blob name using its length
        if req.name.startswith(source_container + "/"):
          output_name = req.name[len(source_container) + 1:]
        
          result = write_to_blob(NEXT_STAGE, f"{output_name}-output.json", response_content)
        
          if result:
              logging.info(f"Successfully wrote output to blob {req.name}")
          else:
              logging.error(f"Failed to write output to blob {req.name}")
    
      except Exception as e:
          logging.error(f"Error processing {paragraphs}: {e}")
          return None
        
    except Exception as e:
      logging.error(f"Error processing {req.name}: {e}")
      return None

# An HTTP-triggered function with a Durable Functions client binding
@app.route(route="client/{functionName}")
@app.durable_client_input(client_name="client")
async def http_start(req: func.HttpRequest, client):
  """
  Starts a new orchestration instance and returns a response to the client.

  args:
    req (func.HttpRequest): The HTTP request object. Contains an array of JSONs with fields: name, url, and container
    client (DurableOrchestrationClient): The Durable Functions client.
  response:
    func.HttpResponse: The HTTP response object.
  """
  
  body = req.get_json()
  logging.info(f"Request body: {body}")

  blobs = body.get("blobs", [])
  # Validate the blobs array
  if not blobs or not isinstance(blobs, list):
      return func.HttpResponse(
        "Invalid request: 'blobs' must be a non-empty array.",
        status_code=400
      )
  
  function_name = req.route_params.get('functionName')
  instance_id = await client.start_new(function_name, client_input=blobs)
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

  for blob in input_data:
    logging.info(f"Calling sub orchestrator for blob: {blob}")
    sub_tasks.append(context.call_sub_orchestrator("ProcessBlob", blob))

  logging.info(f"Sub tasks: {sub_tasks}")

  # Runs a list of asynchronous tasks in parallel and waits for all of them to complete. In this case, the tasks are sub-orchestrations that process each blob in parallel
  results = yield context.task_all(sub_tasks)
  logging.info(f"Results: {results}")
  return results

#Sub orchestrator
@app.function_name(name="ProcessBlob")
@app.orchestration_trigger(context_name="context")
def process_blob(context):
  blob = context.get_input()
  sub_orchestration_id = context.instance_id 
  logging.info(f"Process Blob sub Orchestration - Processing blob: {blob} with sub orchestration id: {sub_orchestration_id}")
  # Waits for the result of an activity function that retrieves the blob content
  text_result = yield context.call_activity("runDocIntel", blob)

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
          "blob_name": blob["name"]
      }
  )
  return {
      "blob": blob,
      "text_result": text_result,
      "task_result": task_result
  }   

app.register_functions(getBlobContent.bp)
app.register_functions(runDocIntel.bp)
app.register_functions(callAoai.bp)
app.register_functions(writeToBlob.bp)