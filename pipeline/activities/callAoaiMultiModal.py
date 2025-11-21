import azure.durable_functions as df

from pipelineUtils.prompts import load_prompts
from pipelineUtils.blob_functions import get_blob_content, write_to_blob
from pipelineUtils.azure_openai import run_prompt
import base64
import json
import fitz # PyMuPDF
from PyPDF2 import PdfReader, PdfWriter  # 👈 for PDF trimming
import logging

from pipelineUtils.prompts import load_prompts
from pipelineUtils.blob_functions import get_blob_content, write_to_blob
from pipelineUtils.azure_openai import run_prompt

name = "callAoaiMultimodal"
bp = df.Blueprint()

def convert_to_base64_images(blob_input: dict):
    """Convert PDF pages or PNG image to base64-encoded images."""
    blob_name = blob_input.get("name")
    container = blob_input.get('container')
    blob_content = get_blob_content(
        container_name=container,
        blob_path=blob_name
    )

    if blob_name.lower().endswith('.pdf'):
        # Process PDF: Convert each page to base64-encoded image
        try:

            base64_images = []
            with fitz.open(stream=blob_content, filetype='pdf') as doc:
                for page in doc:
                    # Render page to a pixmap (image)
                    pix = page.get_pixmap()
                    # Convert pixmap to PNG bytes
                    img_bytes = pix.tobytes("png")
                    # Encode to base64
                    b64 = base64.b64encode(img_bytes).decode("utf-8")
                    base64_images.append(b64)

        except Exception as e:
            logging.error(f"[Silver] PDF trimming or encoding failed: {e}")
            raise

    elif blob_name.lower().endswith('.png'):
        
        # Process PNG: Directly encode the image to base64
        try:
            b64 = base64.b64encode(blob_content).decode("utf-8")
            base64_images = [b64]

        except Exception as e:
            logging.error(f"[Silver] PNG encoding failed: {e}")
            raise
    return base64_images

@bp.function_name(name)
@bp.activity_trigger(input_name="blob_input")
def run(blob_input: dict):
    # Parse args
    blob_name = blob_input.get("name")
    container = blob_input.get('container')
    instance_id = blob_input.get('instance_id', '')

    blob_content = get_blob_content(
        container_name=container,
        blob_path=blob_name
    )


    base64_images = convert_to_base64_images(blob_input)

    prompt_json = load_prompts()

    system_prompt = prompt_json['system_prompt']

    full_user_prompt = (
        f"{prompt_json['user_prompt']}\n\n"
    )
    response_content = run_prompt(instance_id, system_prompt, full_user_prompt, base64_images=base64_images)

