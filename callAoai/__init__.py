import azure.functions as func
import logging
import os
from utils.prompts import load_prompts
from utils.blob_functions import get_blob_content, write_to_blob, list_blobs
# from utils.aoai_functions import call_aoai
from utils.azure_openai import run_prompt
import datetime

current_date = datetime.date.today()
month = current_date.month
day = current_date.day

# # Get Top_p and Temperature values
# TOP_P = float(os.getenv("TOP_P"))
# TEMPERATURE = float(os.getenv("TEMPERATURE"))
# OPENAI_CHAT_MODEL = os.getenv("OPENAI_CHAT_MODEL")

# Comment out following code to process blob trigger
# def main(myblob: func.InputStream):
#   logging.info(f"Processing blob \n"
#               f"Name: {myblob.name}\n"
#               f"Blob Size: {myblob.length} bytes")

def main(req: func.HttpRequest):
  logging.info('Python HTTP trigger function processed a request.')
  
  logging.info("Loading Prompts")
  
  try: 
    prompts = load_prompts()

    # Step 1: Access individual prompts and context
    system_prompt = prompts["system_prompt"]
    user_prompt = prompts["user_prompt"]

    content = myblob.read().decode('utf-8') #Expects .txt file
    logging.info(f"content {content}")
    
    full_user_prompt=user_prompt+content

    #Step 2: Call OpenAI to generate table from drug content and text file as context
    response_content = run_prompt(system_prompt,full_user_prompt)

  
    if response_content.startswith('```json') and response_content.endswith('```'):
      # Strip backticks and "json"
      response_content = response_content.strip('`')
      response_content = response_content.replace('json', '', 1).strip()

    
    json_bytes = response_content.encode('utf-8')
    
    #Step 3: Write the response to a blob
    logging.info("Step 4: Writing response to blob")
    sourcefile = os.path.splitext(os.path.basename(myblob.name))[0]
    logging.info(f"sourcefile: {sourcefile}")
    write_to_blob("gold", f"{sourcefile}-output.json", json_bytes)
      
  except Exception as e:
    logging.error(f"Error: {e}")
    pass