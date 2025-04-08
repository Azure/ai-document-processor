import azure.functions as func
import azure.durable_functions as df
from activities import getBlobContent, runDocIntel, callAoai
app = df.DFApp(http_auth_level=func.AuthLevel.ANONYMOUS)
import logging
# An HTTP-triggered function with a Durable Functions client binding
@app.route(route="orchestrators/{functionName}")
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
  logging.info(f"Started orchestration with ID = '{instance_id}'.")

  response = client.create_check_status_response(req, instance_id)
  return response

# Orchestrator
@app.function_name(name="orchestrator")
@app.orchestration_trigger(context_name="context")
def run(context):
  input_data = context.get_input()
  logging.info(f"Input data: {input_data}")
  
  sub_tasks = []

  for blob in input_data:
    sub_tasks.append(context.call_sub_orchestrator("ProcessBlob", blob))

  results = yield context.task_all(sub_tasks)
  return results

#Sub orchestrator
@app.function_name(name="ProcessBlob")
@app.orchestration_trigger(context_name="context")
def process_blob(context):
    blob = context.get_input()
    text_result = yield context.call_activity("runDocIntel", blob)
    json_result = yield context.call_activity("callAoai", text_result)
    task_result = yield context.call_activity("writeToBlob", json_result)
    return {
        "blob": blob,
        "text_result": text_result,
        "json_result": json_result,
        "task_result": task_result
    }


app.register_functions(getBlobContent.bp)
app.register_functions(runDocIntel.bp)
app.register_functions(callAoai.bp)