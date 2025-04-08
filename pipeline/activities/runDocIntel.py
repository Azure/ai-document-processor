import azure.durable_functions as df
import logging
from utils.blob_functions import list_blobs, get_blob_content, write_to_blob
from utils import get_month_date
# Libraries used in the future Document Processing client code
from azure.identity import DefaultAzureCredential
from azure.ai.documentintelligence import DocumentIntelligenceClient
from azure.ai.documentintelligence.models import AnalyzeResult, AnalyzeDocumentRequest
import base64
import os


# Variables used by Document Processing client code
endpoint =os.getenv("AIMULTISERVICES_ENDPOINT") # Add the AI Services Endpoint value from Azure Function App settings

name = "runDocIntel"
bp = df.Blueprint()

@bp.function_name(name)
@bp.activity_trigger(input_name="blobObj")
def extract_text_from_blob(blobObj: dict):
  try:
    credential = DefaultAzureCredential()                
    client = DocumentIntelligenceClient(
        endpoint=endpoint, credential=credential
    )
    

    poller = client.begin_analyze_document_from_url(
        # AnalyzeDocumentRequest Class: https://learn.microsoft.com/en-us/python/api/azure-ai-documentintelligence/azure.ai.documentintelligence.models.analyzedocumentrequest?view=azure-python
        "prebuilt-read", document_url=blobObj["url"])
    
    result: AnalyzeResult = poller.result()
    
    if result.paragraphs:    
        paragraphs = "\n".join([paragraph.content for paragraph in result.paragraphs])            
    
    return paragraphs
      
  except Exception as e:
    logging.error(f"Error processing {blobObj}: {e}")
    return None
