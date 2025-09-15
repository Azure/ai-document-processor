import azure.durable_functions as df
import logging
from pipelineUtils.blob_functions import list_blobs, get_blob_content, write_to_blob
import os

from configuration import Configuration
config = Configuration()

NEXT_STAGE = config.get_value("NEXT_STAGE")
logging.info(f"writeToBlob.py: NEXT_STAGE is {NEXT_STAGE}")
name = "writeToBlob"
bp = df.Blueprint()

@bp.function_name(name)
@bp.activity_trigger(input_name="args")
def extract_text_from_blob(args: dict):
  """
  Writes the JSON bytes to a blob storage.
  Args:
      args (dict): A dictionary containing the blob name and JSON bytes.
  """
  try:
      args['json_bytes'] = args['json_str'].encode('utf-8')
      
      sourcefile = os.path.splitext(os.path.basename(args['blob_name']))[0]
      logging.info(f"writeToBlob.py: Writing output to blob {sourcefile}-output.json with source file {sourcefile} and NEXT_STAGE {NEXT_STAGE}")
      result = write_to_blob(NEXT_STAGE, f"{sourcefile}-output.json", args['json_bytes'])
      logging.info(f"writeToBlob.py: Result of write_to_blob: {result}")
      if result:
          logging.info(f"writeToBlob.py: Successfully wrote output to blob {args['blob_name']}")
          return {
              "success": True,
              "blob_name": args['blob_name'],
              "output_blob": f"{sourcefile}-output.json"
          }
      else:
          logging.error(f"Failed to write output to blob {args['blob_name']}")
          return {
              "success": False,
              "error": "Failed to write output"
          }
  except Exception as e:
      error_msg = f"Error writing output for blob {args['blob_name']}: {str(e)}"
      logging.error(error_msg)
      return {
          "success": False,
          "error": error_msg
      }
