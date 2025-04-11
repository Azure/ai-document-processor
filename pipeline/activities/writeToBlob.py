import azure.durable_functions as df
import logging
from pipelineUtils.blob_functions import list_blobs, get_blob_content, write_to_blob
import os


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
      result = write_to_blob("gold", f"{sourcefile}-output.json", args['json_bytes'])
      
      if result:
          logging.info(f"Successfully wrote output to blob {args['blob_name']}")
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
