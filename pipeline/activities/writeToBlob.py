import azure.durable_functions as df
import logging
from pipelineUtils.blob_functions import list_blobs, get_blob_content, write_to_blob
import os

from configuration import Configuration
config = Configuration()

FINAL_OUTPUT_CONTAINER = config.get_value("FINAL_OUTPUT_CONTAINER")

logging.info(f"writeToBlob.py: FINAL_OUTPUT_CONTAINER is {FINAL_OUTPUT_CONTAINER}")

name = "writeToBlob"
bp = df.Blueprint()

@bp.function_name(name)
@bp.activity_trigger(input_name="args")
def write_to_blob_activity(args: dict):
  """
  Writes the JSON bytes to a blob storage.
  Args:
      args (dict): A dictionary containing the blob name and JSON bytes.
  """
  try:
        # Parse arguments
      blob_name = args['blob_name']
      final_output_container = args['final_output_container']
      json_str = args['json_str']
      
      args['json_bytes'] = json_str.encode('utf-8')

      sourcefile = os.path.splitext(os.path.basename(blob_name))[0]
      logging.info(f"writeToBlob.py: Writing output to blob {sourcefile}-output.json with source file {sourcefile} and FINAL_OUTPUT_CONTAINER {final_output_container}")
      result = write_to_blob(final_output_container, f"{sourcefile}-output.json", args['json_bytes'])
      logging.info(f"writeToBlob.py: Result of write_to_blob: {result}")
      if result:
          logging.info(f"writeToBlob.py: Successfully wrote output to blob {blob_name}")
          return {
              "success": True,
              "blob_name": blob_name,
              "output_blob": f"{sourcefile}-output.json"
          }
      else:
          logging.error(f"Failed to write output to blob {blob_name}")
          return {
              "success": False,
              "error": "Failed to write output"
          }
  except Exception as e:
      error_msg = f"Error writing output for blob {blob_name}: {str(e)}"
      logging.error(error_msg)
      return {
          "success": False,
          "error": error_msg
      }
