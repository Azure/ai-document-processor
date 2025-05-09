import azure.functions as func
import azure.durable_functions as df
from activities import getBlobContent, runDocIntel, callAoai, writeToBlob
app = df.DFApp(http_auth_level=func.AuthLevel.ANONYMOUS)
import logging
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