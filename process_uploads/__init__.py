import azure.functions as func
import logging
from docx import Document
import fitz
from utils.blob_functions import list_blobs, get_blob_content, write_to_blob
from utils import get_month_date
import io
import os
from openai import AzureOpenAI
from azure.identity import DefaultAzureCredential

def extract_text_from_docx(blob_name):
  try:
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
  except Exception as e:
    logging.error(f"Error processing {blob_name}: {e}")
    return None

def extract_text_from_pdf(blob_name):
    try:
      # Get the content of the blob
      content = get_blob_content("bronze", blob_name)
      # Load the PDF document
      doc = fitz.open(stream=content, filetype="pdf")
      # Extract text from all pages
      text = "\n".join(page.get_text() for page in doc)
      return text
    except Exception as e:
      logging.error(f"Error processing {blob_name}: {e}")
      return None

def main(req: func.HttpRequest):
  logging.info('Python HTTP trigger function processed a request.')

  month, date = get_month_date()
# Lists blobs in ui-uploads container
  for blob in list_blobs('bronze'):
    try:
      blob_name = blob.name

      if blob_name.endswith(".docx"):
        logging.info(f"Docx: {blob_name}")
        text = extract_text_from_docx(blob_name)  
        sourcefile = os.path.splitext(os.path.basename(blob_name))[0]
        write_to_blob(f"silver", f"{month}/{date}/{sourcefile}.txt", text)

      elif blob_name.endswith(".pdf"):
        logging.info(f"PDF: {blob_name}")
        text = extract_text_from_pdf(blob_name)
        sourcefile = os.path.splitext(os.path.basename(blob_name))[0]
        write_to_blob(f"silver", f"{sourcefile}.txt", text)

      else:
        logging.info(f"Other File {blob_name}")
    
    except Exception as e:
      logging.error(f"Error processing {blob_name}: {e}")
      continue