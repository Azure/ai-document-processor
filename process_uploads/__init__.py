import azure.functions as func
import logging
from docx import Document
from utils.blob_functions import list_blobs, get_blob_content, write_to_blob
from utils import get_month_date
import io
import os
from openai import AzureOpenAI
from azure.identity import DefaultAzureCredential

def extract_text_from_docx(blob_name):
  # Get the content of the blob
  content = get_blob_content("bronze", blob_name)
  # Load the content into a Document object
  doc = Document(io.BytesIO(content))
  # Extract and print the text
  full_text = []
  for paragraph in doc.paragraphs:
      full_text.append(paragraph.text)

  # Combine paragraphs into a single string
  text = "\n".join(full_text)
  return text


# def call_whisper(blob_name):
#   audio_content = get_blob_content("bronze", blob_name)
  
#   credential = DefaultAzureCredential()

#   token = credential.get_token("https://openai.azure.com/.default").token
#   client = AzureOpenAI(
#       azure_ad_token=token,
#       api_version="2024-02-01",
#       azure_endpoint = os.getenv("OPENAI_API_BASE")
#   )

#   deployment_id = "whisper" #This will correspond to the custom name you chose for your deployment when you deployed a model."

#   result = client.audio.transcriptions.create(
#       file=audio_content,            
#       model=deployment_id
#   )

#   print(result)

def main(req: func.HttpRequest):
  logging.info('Python HTTP trigger function processed a request.')

  month, date = get_month_date()
# Lists blobs in ui-uploads container
  for blob in list_blobs('bronze'):
    blob_name = blob.name

    if blob_name.endswith(".docx"):
      logging.info(f"Docx: {blob_name}")
      text = extract_text_from_docx(blob_name)  
      sourcefile = os.path.splitext(os.path.basename(blob_name))[0]
      write_to_blob(f"silver", f"{month}/{date}/{sourcefile}.txt", text)

    elif blob_name.endswith((".mp3", ".m4a", ".wav", ".mp4" ".aac")):
      logging.info(f"Audio: {blob_name}")
      # response=call_whisper(blob_name)
      # sourcefile = os.path.splitext(os.path.basename(blob_name))[0]
      # write_to_blob(f"silver", f"{month}/{date}/{sourcefile}.txt", response.text)