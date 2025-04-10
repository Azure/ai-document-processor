import azure.durable_functions as df
from pipelineUtils.blob_functions import get_blob_content
import logging

name = "getBlobContent"
bp = df.Blueprint()

@bp.function_name(name)
@bp.activity_trigger(input_name="blobObj")
def run(blobObj: dict):
    logging.info(f"BlobObj: {blobObj}")
    return f"Get Blob Content: {blobObj}"