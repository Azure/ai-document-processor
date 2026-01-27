import azure.durable_functions as df
import azure.cognitiveservices.speech as speechsdk
import logging
import tempfile
import os
import io
import time
import requests
import uuid
import zipfile
import html
import re
from pipelineUtils.blob_functions import get_blob_content, write_to_blob
from configuration import Configuration

name = "voiceToVoiceTranslation"
bp = df.Blueprint()

# Voice mapping for common languages
VOICE_MAP = {
    "es": "es-ES-ElviraNeural",
    "es-MX": "es-MX-DaliaNeural",
    "fr": "fr-FR-DeniseNeural",
    "de": "de-DE-KatjaNeural",
    "it": "it-IT-ElsaNeural",
    "pt": "pt-BR-FranciscaNeural",
    "zh": "zh-CN-XiaoxiaoNeural",
    "ja": "ja-JP-NanamiNeural",
    "ko": "ko-KR-SunHiNeural",
    "en": "en-US-AriaNeural"
}

def normalize_blob_name(container: str, raw_name: str) -> str:
    """Strip container prefix if included in the name."""
    if raw_name.startswith(container + "/"):
        return raw_name[len(container) + 1:]
    return raw_name

def convert_audio_format(audio_data: bytes, source_format: str, target_format: str) -> bytes:
    """
    Convert audio from WAV (source_format) to target format.
    
    Note: Azure Speech Service always outputs WAV format. This function converts
    the WAV output to match the source file format when possible.
    
    Args:
        audio_data: WAV audio data bytes
        source_format: Source format extension (e.g., '.mp3', '.wav')
        target_format: Target format extension (should match source_format)
    
    Returns:
        Converted audio data bytes, or original WAV if conversion not possible
    """
    # If formats are the same or target is WAV, return as-is
    if source_format.lower() == target_format.lower() or target_format.lower() == '.wav':
        return audio_data
    
    # Try to use pydub for format conversion if available
    try:
        from pydub import AudioSegment
        from pydub.utils import which
        
        # Check if ffmpeg is available (required for format conversion)
        if not which("ffmpeg"):
            logging.warning(f"ffmpeg not available - cannot convert WAV to {target_format}. Output will remain WAV format.")
            return audio_data
        
        # Load WAV from bytes
        audio = AudioSegment.from_wav(io.BytesIO(audio_data))
        
        # Export to target format
        output = io.BytesIO()
        format_name = target_format.lstrip('.').lower()
        
        # Map format names for pydub
        format_map = {
            'mp3': 'mp3',
            'm4a': 'm4a',
            'flac': 'flac',
            'ogg': 'ogg',
            'opus': 'opus',
            'aac': 'aac',
            'wma': 'wma',
            'webm': 'webm'
        }
        
        export_format = format_map.get(format_name, 'wav')
        
        if export_format == 'mp3':
            audio.export(output, format='mp3', bitrate='192k')
        elif export_format in ['m4a', 'aac']:
            audio.export(output, format='ipod', codec='aac')
        elif export_format == 'flac':
            audio.export(output, format='flac')
        elif export_format == 'ogg':
            audio.export(output, format='ogg', codec='libvorbis')
        elif export_format == 'opus':
            audio.export(output, format='ogg', codec='libopus')
        elif export_format == 'webm':
            audio.export(output, format='webm', codec='libopus')
        else:
            logging.warning(f"Unsupported target format {target_format}, keeping WAV")
            return audio_data
        
        converted_data = output.getvalue()
        logging.info(f"Converted audio from WAV to {target_format} ({len(audio_data)} -> {len(converted_data)} bytes)")
        return converted_data
        
    except ImportError:
        logging.warning("pydub not available - cannot convert audio format. Install with: pip install pydub")
        logging.warning(f"Output will remain WAV format even though extension is {target_format}")
        return audio_data
    except Exception as e:
        logging.warning(f"Error converting audio format: {e}. Output will remain WAV format.")
        return audio_data

def wait_for_batch_transcription(transcription_url: str, headers: dict, check_interval: int = 10, max_wait_time: int = 7200):
    """Poll the batch transcription status until it's complete"""
    elapsed_time = 0
    last_log_time = 0
    log_interval = 30  # Log every 30 seconds for running status
    
    logging.info(f"Starting batch transcription polling (max wait time: {max_wait_time // 60} minutes)")
    
    while elapsed_time < max_wait_time:
        status_response = requests.get(transcription_url, headers=headers)
        status_response.raise_for_status()
        status = status_response.json()
        
        current_status = status.get('status', 'Unknown')
        
        if current_status == 'Succeeded':
            minutes, seconds = divmod(elapsed_time, 60)
            logging.info(f"Batch transcription completed successfully! Total time: {int(minutes)}m {int(seconds)}s")
            return status
        elif current_status == 'Failed':
            error_msg = status.get('properties', {}).get('error', 'Unknown error')
            minutes, seconds = divmod(elapsed_time, 60)
            logging.error(f"Batch transcription failed after {int(minutes)}m {int(seconds)}s: {error_msg}")
            raise Exception(f"Batch transcription failed: {error_msg}")
        else:
            # Log less frequently for "Running" status to reduce log noise
            if elapsed_time - last_log_time >= log_interval or elapsed_time == 0:
                minutes, seconds = divmod(elapsed_time, 60)
                hours, minutes = divmod(minutes, 60)
                time_str = f"{int(hours)}h {int(minutes)}m {int(seconds)}s" if hours > 0 else f"{int(minutes)}m {int(seconds)}s"
                
                # Include any additional status information if available
                status_info = ""
                if 'createdDateTime' in status:
                    status_info = f" (Created: {status['createdDateTime']})"
                
                logging.info(f"Batch transcription status: {current_status} - Elapsed time: {time_str}{status_info}")
                last_log_time = elapsed_time
            
            time.sleep(check_interval)
            elapsed_time += check_interval
    
    minutes, seconds = divmod(max_wait_time, 60)
    hours, minutes = divmod(minutes, 60)
    time_str = f"{int(hours)}h {int(minutes)}m" if hours > 0 else f"{int(minutes)}m"
    raise Exception(f"Batch transcription timed out after {time_str} ({max_wait_time} seconds)")

def batch_transcribe_audio(blob_uri: str, source_language: str, endpoint: str, token: str, api_version: str = "2025-10-15") -> str:
    """Use batch transcription API to transcribe audio file"""
    url = f"{endpoint}/speechtotext/transcriptions:submit?api-version={api_version}"
    
    headers = {
        'Content-Type': 'application/json',
        "Authorization": f"Bearer {token}",
    }
    
    payload = {
        "displayName": f"Translation transcription {uuid.uuid4()}",
        "locale": source_language,
        "contentUrls": [blob_uri],
        "properties": {
            "wordLevelTimestampsEnabled": False,
            "displayFormWordLevelTimestampsEnabled": False,
            "punctuationMode": "DictatedAndAutomatic",
            "profanityFilterMode": "Masked",
            "timeToLiveHours": 48
        }
    }
    
    logging.info(f"Submitting batch transcription request for: {blob_uri}")
    response = requests.post(url, json=payload, headers=headers)
    response.raise_for_status()
    transcription_url = response.json()['self']
    
    # Wait for completion
    final_status = wait_for_batch_transcription(transcription_url, headers)
    
    # Get transcription results
    files_url = final_status['links']['files']
    files_response = requests.get(files_url, headers=headers)
    files_response.raise_for_status()
    content_url = files_response.json()['values'][0]['links']['contentUrl']
    
    # Check if content URL has SAS token (query parameters) - if so, don't use Authorization header
    # SAS token URLs don't need Authorization headers, and including them causes 403 errors
    if '?' in content_url and ('sig=' in content_url or 'skt=' in content_url):
        # URL contains SAS token - don't include Authorization header
        logging.info("Content URL contains SAS token, using token-based authentication")
        content_response = requests.get(content_url)
    else:
        # URL doesn't have SAS token - use Authorization header
        logging.info("Content URL doesn't contain SAS token, using Authorization header")
        content_response = requests.get(content_url, headers=headers)
    
    content_response.raise_for_status()
    content_json = content_response.json()
    
    # Extract full text from transcription
    if not content_json.get('combinedRecognizedPhrases') or len(content_json['combinedRecognizedPhrases']) == 0:
        raise Exception("No transcription results found in batch transcription response")
    
    full_text = content_json['combinedRecognizedPhrases'][0]['display']
    
    if not full_text or len(full_text.strip()) == 0:
        raise Exception("Transcription returned empty text")
    
    logging.info(f"Batch transcription completed. Text length: {len(full_text)} characters")
    
    return full_text

def translate_text(text: str, source_language: str, target_language: str, endpoint: str, token: str, region: str, config: Configuration = None) -> str:
    """Translate text using Translator API"""
    # Map language codes (e.g., "en-US" -> "en", "es" -> "es")
    source_lang_code = source_language.split('-')[0] if '-' in source_language else source_language
    target_lang_code = target_language.split('-')[0] if '-' in target_language else target_language
    
    # Get Translator API subscription key or endpoint from config
    translator_key = None
    translator_endpoint = None
    
    if config:
        try:
            translator_key = config.get_value("TRANSLATOR_KEY", None)
            if translator_key and isinstance(translator_key, str) and translator_key.strip() == "":
                translator_key = None
        except Exception:
            pass
        
        try:
            translator_endpoint = config.get_value("TRANSLATOR_ENDPOINT", None)
            if translator_endpoint and isinstance(translator_endpoint, str) and translator_endpoint.strip() == "":
                translator_endpoint = None
        except Exception:
            pass
    
    # Determine endpoint and authentication method
    if not translator_endpoint:
        if translator_key:
            # Subscription key auth: use global endpoint
            translator_endpoint = "https://api.cognitive.microsofttranslator.com"
            logging.info(f"Using global Translator endpoint for subscription key auth")
        else:
            # Managed identity auth: use resource endpoint (from endpoint parameter)
            # This is the AI Multi-Services endpoint like: https://aimsa-xxx.cognitiveservices.azure.com
            translator_endpoint = endpoint
            logging.info(f"Using resource endpoint for managed identity auth: {translator_endpoint}")
    
    # Remove trailing slashes
    translator_endpoint = translator_endpoint.rstrip('/')
    
    # Construct the full Translator API URL
    # For resource endpoints with managed identity: /translator/text/v3.0/translate
    # For global endpoint with key: /translate
    if translator_key:
        translator_url = f"{translator_endpoint}/translate?api-version=3.0&from={source_lang_code}&to={target_lang_code}"
    else:
        # Managed identity with resource endpoint needs the full path
        translator_url = f"{translator_endpoint}/translator/text/v3.0/translate?api-version=3.0&from={source_lang_code}&to={target_lang_code}"
    
    logging.info(f"Translator API URL: {translator_url}")
    
    # Set up authentication headers
    if translator_key:
        # Use subscription key authentication
        headers = {
            'Content-Type': 'application/json',
            'Ocp-Apim-Subscription-Key': translator_key,
        }
        logging.info("Using Translator API with subscription key authentication")
    else:
        # Use managed identity with Bearer token
        # For managed identity, we need both Authorization header and Ocp-Apim-ResourceId header
        # Get Translator resource ID from config, or use Speech resource ID as fallback
        translator_resource_id = None
        if config:
            try:
                translator_resource_id = config.get_value("TRANSLATOR_RESOURCE_ID", None)
                if translator_resource_id and isinstance(translator_resource_id, str) and translator_resource_id.strip() == "":
                    translator_resource_id = None
            except Exception:
                pass
        
        # If no Translator resource ID, try to use Speech resource ID (if Translator is part of multi-service resource)
        if not translator_resource_id and config:
            try:
                # Use Speech resource ID as fallback (Translator might be in same multi-service resource)
                speech_resource_id = config.get_value("AIMULTISERVICES_RESOURCE_ID", None)
                if speech_resource_id and isinstance(speech_resource_id, str) and speech_resource_id.strip() != "":
                    translator_resource_id = speech_resource_id
                    logging.info("Using Speech resource ID for Translator API (assuming Translator is in same multi-service resource)")
            except Exception:
                pass
        
        if translator_resource_id:
            headers = {
                'Content-Type': 'application/json',
                "Authorization": f"Bearer {token}",
                "Ocp-Apim-ResourceId": translator_resource_id,
                "Ocp-Apim-Subscription-Region": region,
            }
            logging.info(f"Using Translator API with managed identity authentication")
            logging.info(f"  Endpoint: {translator_endpoint}")
            logging.info(f"  Resource ID: {translator_resource_id[:50]}...")
            logging.info(f"  Region: {region}")
        else:
            # Fallback: try without ResourceId (may work if Translator is in same multi-service resource)
            headers = {
                'Content-Type': 'application/json',
                "Authorization": f"Bearer {token}",
            }
            logging.warning("Using Translator API with managed identity but no Resource ID - this may fail if Translator is a separate resource")
    
    # Split text into chunks if too long (Translator API has limits - max 50,000 characters per request)
    max_chunk_size = 50000  # characters per chunk
    translated_chunks = []
    
    for i in range(0, len(text), max_chunk_size):
        chunk = text[i:i + max_chunk_size]
        body = [{"text": chunk}]
        
        chunk_num = i // max_chunk_size + 1
        total_chunks = (len(text) + max_chunk_size - 1) // max_chunk_size
        logging.info(f"Translating text chunk {chunk_num}/{total_chunks} ({len(chunk)} characters)...")
        
        try:
            response = requests.post(translator_url, json=body, headers=headers)
            
            # Check for authentication errors
            if response.status_code == 401:
                error_detail = response.text
                logging.error(f"Translator API authentication failed (401). Response: {error_detail}")
                logging.error(f"Request URL: {translator_url}")
                if not translator_key:
                    logging.error("Using managed identity authentication. Troubleshooting checklist:")
                    logging.error(f"  1. Endpoint: {translator_endpoint} (should be regional, not global)")
                    logging.error(f"  2. Resource ID: {translator_resource_id if 'translator_resource_id' in locals() else 'Not set'}")
                    logging.error(f"  3. Region: {region}")
                    logging.error("  4. Verify managed identity has 'Cognitive Services User' role on the resource")
                    logging.error("  5. Verify Translator is enabled in the AI Multi-Services resource")
                else:
                    logging.error("Using subscription key. Verify TRANSLATOR_KEY is correct.")
                raise Exception(f"Translator API authentication failed: {error_detail}")
            
            response.raise_for_status()
            
            translated_text = response.json()[0]['translations'][0]['text']
            translated_chunks.append(translated_text)
        except requests.exceptions.HTTPError as e:
            logging.error(f"HTTP error translating chunk {chunk_num}: {e}")
            if e.response is not None:
                logging.error(f"Response status: {e.response.status_code}, Response body: {e.response.text}")
            raise
        except Exception as e:
            logging.error(f"Error translating chunk {chunk_num}: {e}")
            raise
    
    full_translated_text = " ".join(translated_chunks)
    logging.info(f"Translation completed. Translated text length: {len(full_translated_text)} characters")
    
    return full_translated_text

def wait_for_batch_synthesis(synthesis_url: str, headers: dict, check_interval: int = 10, max_wait_time: int = 7200):
    """Poll the batch synthesis status until it's complete"""
    elapsed_time = 0
    last_log_time = 0
    log_interval = 30  # Log every 30 seconds for running status
    
    logging.info(f"Starting batch synthesis polling (max wait time: {max_wait_time // 60} minutes)")
    
    while elapsed_time < max_wait_time:
        status_response = requests.get(synthesis_url, headers=headers)
        status_response.raise_for_status()
        status = status_response.json()
        
        current_status = status.get('status', 'Unknown')
        
        if current_status == 'Succeeded':
            minutes, seconds = divmod(elapsed_time, 60)
            logging.info(f"Batch synthesis completed successfully! Total time: {int(minutes)}m {int(seconds)}s")
            return status
        elif current_status == 'Failed':
            error_msg = status.get('properties', {}).get('error', 'Unknown error')
            minutes, seconds = divmod(elapsed_time, 60)
            logging.error(f"Batch synthesis failed after {int(minutes)}m {int(seconds)}s: {error_msg}")
            raise Exception(f"Batch synthesis failed: {error_msg}")
        else:
            # Log less frequently for "Running" status to reduce log noise
            if elapsed_time - last_log_time >= log_interval or elapsed_time == 0:
                minutes, seconds = divmod(elapsed_time, 60)
                hours, minutes = divmod(minutes, 60)
                time_str = f"{int(hours)}h {int(minutes)}m {int(seconds)}s" if hours > 0 else f"{int(minutes)}m {int(seconds)}s"
                
                # Include any additional status information if available
                status_info = ""
                if 'createdDateTime' in status:
                    status_info = f" (Created: {status['createdDateTime']})"
                
                logging.info(f"Batch synthesis status: {current_status} - Elapsed time: {time_str}{status_info}")
                last_log_time = elapsed_time
            
            time.sleep(check_interval)
            elapsed_time += check_interval
    
    minutes, seconds = divmod(max_wait_time, 60)
    hours, minutes = divmod(minutes, 60)
    time_str = f"{int(hours)}h {int(minutes)}m" if hours > 0 else f"{int(minutes)}m"
    raise Exception(f"Batch synthesis timed out after {time_str} ({max_wait_time} seconds)")

def batch_synthesize_audio(text: str, target_language: str, voice_name: str, endpoint: str, token: str, region: str, api_version: str = "2024-04-01") -> bytes:
    """Use batch synthesis API to convert translated text to audio"""
    synthesis_id = f"v2v-{uuid.uuid4().hex[:16]}"
    url = f"{endpoint}/texttospeech/batchsyntheses/{synthesis_id}?api-version={api_version}"
    
    headers = {
        'Content-Type': 'application/json',
        "Authorization": f"Bearer {token}",
    }
    
    # Split text into chunks if too long (max 2MB JSON payload)
    # Each character is roughly 1 byte, so we'll use 1.5MB to be safe
    max_text_size = 1500000  # characters
    text_chunks = []
    
    if len(text) > max_text_size:
        # Split by sentences (handle multiple sentence endings)
        # Split on common sentence endings: . ! ? followed by space
        sentence_pattern = r'([.!?]\s+)'
        sentences = re.split(sentence_pattern, text)
        # Recombine sentences with their endings
        combined_sentences = []
        for i in range(0, len(sentences) - 1, 2):
            if i + 1 < len(sentences):
                combined_sentences.append(sentences[i] + sentences[i + 1])
            else:
                combined_sentences.append(sentences[i])
        if len(sentences) % 2 == 1:
            combined_sentences.append(sentences[-1])
        
        current_chunk = ""
        for sentence in combined_sentences:
            sentence_len = len(sentence)
            if len(current_chunk) + sentence_len > max_text_size:
                if current_chunk:
                    text_chunks.append(current_chunk.strip())
                current_chunk = sentence
            else:
                current_chunk += sentence
        if current_chunk:
            text_chunks.append(current_chunk.strip())
    else:
        text_chunks = [text]
    
    # Create SSML with voice (escape XML special characters)
    ssml_inputs = []
    for chunk in text_chunks:
        # Escape XML/HTML special characters
        escaped_chunk = html.escape(chunk)
        ssml = f'<speak version="1.0" xml:lang="{target_language}"><voice xml:lang="{target_language}" name="{voice_name}">{escaped_chunk}</voice></speak>'
        ssml_inputs.append({"content": ssml})
    
    payload = {
        "inputKind": "SSML",
        "inputs": ssml_inputs,
        "properties": {
            "concatenateResult": True  # Combine all chunks into one audio file
        }
    }
    
    logging.info(f"Submitting batch synthesis request with {len(text_chunks)} text chunks...")
    response = requests.put(url, json=payload, headers=headers)
    response.raise_for_status()
    
    synthesis_url = response.json().get('self') or url
    logging.info(f"Batch synthesis job created: {synthesis_id}")
    
    # Wait for completion
    final_status = wait_for_batch_synthesis(synthesis_url, headers)
    
    # Get synthesis results
    result_url = final_status['outputs']['result']
    logging.info(f"Downloading batch synthesis results from: {result_url}")
    
    # Check if result URL has SAS token (query parameters) - if so, don't use Authorization header
    # SAS token URLs don't need Authorization headers, and including them causes 403 errors
    if '?' in result_url and ('sig=' in result_url or 'skt=' in result_url):
        # URL contains SAS token - don't include Authorization header
        logging.info("Result URL contains SAS token, using token-based authentication")
        result_response = requests.get(result_url)
    else:
        # URL doesn't have SAS token - use Authorization header
        logging.info("Result URL doesn't contain SAS token, using Authorization header")
        result_response = requests.get(result_url, headers=headers)
    
    result_response.raise_for_status()
    
    # Results are in a ZIP file
    zip_data = result_response.content
    with zipfile.ZipFile(io.BytesIO(zip_data)) as zip_file:
        # Find the audio file (usually 0001.wav or similar)
        audio_files = [f for f in zip_file.namelist() if f.endswith('.wav')]
        if not audio_files:
            raise Exception("No audio file found in batch synthesis results")
        
        audio_file = audio_files[0]
        audio_data = zip_file.read(audio_file)
        logging.info(f"Extracted audio file: {audio_file}, size: {len(audio_data)} bytes")
        
        return audio_data

@bp.function_name(name)
@bp.activity_trigger(input_name="blob_input")
def run(blob_input: dict):
    """
    Translates audio file from source language to target language and outputs as audio file.
    
    Args:
        blob_input (dict): Dictionary containing:
            - name: blob name
            - container: container name
            - uri: blob URI
    
    Returns:
        dict: Result containing translated audio blob information
    """
    try:
        blob_name = blob_input.get('name')
        container = blob_input.get('container')
        
        config = Configuration()
        credential = config.credential
        
        # Get Speech service endpoint and credentials
        speech_endpoint = config.get_value("AIMULTISERVICES_ENDPOINT")
        token = credential.get_token("https://cognitiveservices.azure.com/.default").token
        
        # Get resource ID for Microsoft Entra authentication
        resource_id = None
        try:
            resource_id = config.get_value("AIMULTISERVICES_RESOURCE_ID", None)
            if resource_id is None or (isinstance(resource_id, str) and resource_id.strip() == ""):
                resource_id = None
        except Exception:
            resource_id = None
        
        if not resource_id:
            error_msg = (
                "AIMULTISERVICES_RESOURCE_ID is not set in function app settings. "
                "This is required for managed identity authentication."
            )
            logging.error(error_msg)
            raise Exception(error_msg)
        
        # Get target language from environment variable (default to Spanish)
        target_language = config.get_value("TRANSLATION_TARGET_LANGUAGE", "es")
        source_language = config.get_value("TRANSLATION_SOURCE_LANGUAGE", "en-US")
        
        # Get batch processing threshold (default 50MB)
        batch_threshold_mb = float(config.get_value("BATCH_TRANSLATION_THRESHOLD_MB", "50"))
        batch_threshold_bytes = int(batch_threshold_mb * 1024 * 1024)
        
        # Normalize blob name (strip container prefix if present)
        normalized_blob_name = normalize_blob_name(container, blob_name)
        
        # Get blob URI for batch processing
        blob_uri = blob_input.get('uri')
        if not blob_uri:
            # Construct URI if not provided
            storage_account = config.get_value("DATA_STORAGE_ACCOUNT_NAME")
            blob_uri = f"https://{storage_account}.blob.core.windows.net/{container}/{normalized_blob_name}"
        
        # Download audio file from blob storage to check size
        logging.info(f"Downloading audio file: {normalized_blob_name}")
        audio_content = get_blob_content(container, normalized_blob_name)
        file_size_mb = len(audio_content) / (1024 * 1024)
        logging.info(f"Audio file size: {file_size_mb:.2f} MB ({len(audio_content)} bytes)")
        
        # Determine if we should use batch processing
        use_batch_processing = len(audio_content) > batch_threshold_bytes
        logging.info(f"Batch processing threshold: {batch_threshold_mb} MB ({batch_threshold_bytes} bytes)")
        logging.info(f"Using batch processing: {use_batch_processing} (file size: {file_size_mb:.2f} MB)")
        
        # Detect file extension from blob name to use correct format
        file_extension = os.path.splitext(normalized_blob_name)[1].lower()
        # Default to .wav if no extension found, otherwise use the original extension
        temp_suffix = file_extension if file_extension else '.wav'
        # Ensure it starts with a dot
        if not temp_suffix.startswith('.'):
            temp_suffix = '.' + temp_suffix
        
        logging.info(f"Detected file format: {temp_suffix} (from blob name: {normalized_blob_name})")
        
        # Create temporary file for input audio with correct extension
        with tempfile.NamedTemporaryFile(delete=False, suffix=temp_suffix) as temp_input:
            temp_input.write(audio_content)
            temp_input_path = temp_input.name
        
        logging.info(f"Created temporary file: {temp_input_path} with format {temp_suffix}")
        
        try:
            # Extract region from endpoint or config
            try:
                if ".api.cognitive.microsoft.com" in speech_endpoint:
                    region = speech_endpoint.split("//")[1].split(".")[0]
                else:
                    region = config.get_value("SPEECH_SERVICE_REGION", "eastus")
            except Exception:
                region = config.get_value("SPEECH_SERVICE_REGION", "eastus")
            
            # Use batch processing for large files
            if use_batch_processing:
                logging.info("Using batch processing pipeline for large file...")
                
                # Step 1: Batch transcription
                logging.info("Step 1: Starting batch transcription...")
                logging.info(f"Note: Batch transcription is asynchronous and may take several minutes to hours depending on file size ({file_size_mb:.2f} MB) and service load.")
                source_text = batch_transcribe_audio(blob_uri, source_language, speech_endpoint, token)
                
                # Step 2: Translate text
                logging.info("Step 2: Translating text...")
                
                # Get Translator-specific token if Translator resource ID is configured
                # Note: If Translator is a separate resource, you may need to configure
                # TRANSLATOR_RESOURCE_ID and ensure managed identity has access
                translator_token = token
                translator_resource_id = None
                try:
                    translator_resource_id = config.get_value("TRANSLATOR_RESOURCE_ID", None)
                    if translator_resource_id and isinstance(translator_resource_id, str) and translator_resource_id.strip() != "":
                        # If Translator is a separate resource, get a fresh token
                        # The token scope should work for all Cognitive Services in the same tenant
                        translator_token = credential.get_token("https://cognitiveservices.azure.com/.default").token
                        logging.info(f"Using Translator-specific resource ID: {translator_resource_id[:50]}...")
                except Exception as e:
                    logging.warning(f"Could not get Translator-specific token, using default: {e}")
                    pass
                
                translated_text = translate_text(source_text, source_language, target_language, speech_endpoint, translator_token, region, config)
                
                # Step 3: Batch synthesis
                logging.info("Step 3: Starting batch synthesis...")
                text_length = len(translated_text)
                logging.info(f"Note: Batch synthesis may take several minutes depending on text length ({text_length:,} characters) and service load.")
                
                # Get voice name from voice map
                voice_name = VOICE_MAP.get(target_language, f"{target_language}-Neural")
                
                combined_audio = batch_synthesize_audio(translated_text, target_language, voice_name, speech_endpoint, token, region)
                
                # Generate output blob name - preserve source format extension
                base_name = os.path.splitext(os.path.basename(normalized_blob_name))[0]
                # Use source file extension if available, otherwise default to .wav
                output_extension = file_extension if file_extension else '.wav'
                output_blob_name = f"{base_name}_translated_{target_language}{output_extension}"
                
                # Convert WAV output to match source format if different
                if output_extension.lower() != '.wav':
                    logging.info(f"Converting audio from WAV to {output_extension} to match source format")
                    combined_audio = convert_audio_format(combined_audio, '.wav', output_extension)
                
                # Upload translated audio to blob storage
                output_container = config.get_value("FINAL_OUTPUT_CONTAINER", "silver")
                logging.info(f"Uploading translated audio to {output_container}/{output_blob_name}")
                write_to_blob(output_container, output_blob_name, combined_audio)
                
                return {
                    "success": True,
                    "original_blob": blob_name,
                    "translated_blob": output_blob_name,
                    "container": output_container,
                    "target_language": target_language,
                    "translated_text": translated_text,
                    "processing_method": "batch",
                    "file_size_mb": file_size_mb
                }
            
            # Continue with real-time processing for smaller files
            logging.info("Using real-time processing for file...")
            
            # Get subscription key if available, otherwise use managed identity
            speech_key = None
            try:
                speech_key = config.get_value("SPEECH_SERVICE_KEY", None)
                if speech_key is None or (isinstance(speech_key, str) and speech_key.strip() == ""):
                    speech_key = None
            except Exception:
                speech_key = None
            
            # Create speech translation config
            if speech_key:
                speech_translation_config = speechsdk.translation.SpeechTranslationConfig(
                    subscription=speech_key,
                    region=region
                )
            else:
                # Use token authentication with resource ID format: "aad#" + resourceId + "#" + token
                authorization_token = f"aad#{resource_id}#{token}"
                speech_translation_config = speechsdk.translation.SpeechTranslationConfig(
                    auth_token=authorization_token,
                    region=region
                )
            
            # Set languages
            source_language = config.get_value("TRANSLATION_SOURCE_LANGUAGE", "en-US")
            speech_translation_config.speech_recognition_language = source_language
            speech_translation_config.add_target_language(target_language)
            
            # Check if Personal Voice (voice cloning) is enabled
            use_personal_voice = config.get_value("USE_PERSONAL_VOICE", "false").lower() == "true"
            speaker_profile_id = None
            try:
                speaker_profile_id = config.get_value("SPEAKER_PROFILE_ID", None)
                if speaker_profile_id is None or (isinstance(speaker_profile_id, str) and speaker_profile_id.strip() == ""):
                    speaker_profile_id = None
            except Exception:
                speaker_profile_id = None
            
            if use_personal_voice and speaker_profile_id:
                # Use Personal Voice for voice cloning
                v2_endpoint = f"wss://{region}.stt.speech.microsoft.com/speech/universal/v2"
                
                if speech_key:
                    speech_translation_config = speechsdk.translation.SpeechTranslationConfig(
                        subscription=speech_key,
                        endpoint=v2_endpoint
                    )
                else:
                    authorization_token = f"aad#{resource_id}#{token}"
                    speech_translation_config = speechsdk.translation.SpeechTranslationConfig(
                        auth_token=authorization_token,
                        region=region
                    )
                    speech_translation_config.set_property(
                        speechsdk.PropertyId.SpeechServiceConnection_Endpoint,
                        v2_endpoint
                    )
                
                # Re-set language configuration
                speech_translation_config.speech_recognition_language = source_language
                speech_translation_config.add_target_language(target_language)
                speech_translation_config.voice_name = "personal-voice"
                logging.info(f"Using Personal Voice with speaker profile ID: {speaker_profile_id}")
            else:
                # Use standard neural voices
                voice_name = VOICE_MAP.get(target_language, f"{target_language}-Neural")
                speech_translation_config.voice_name = voice_name
                logging.info(f"Using neural voice: {voice_name} for language: {target_language}")
            
            # Configure audio input from file
            # Note: Using correct file extension allows Speech SDK to auto-detect format
            logging.info(f"Configuring audio input from file: {temp_input_path} (format: {file_extension})")
            audio_config = speechsdk.audio.AudioConfig(filename=temp_input_path)
            
            # Create translation recognizer
            translation_recognizer = speechsdk.translation.TranslationRecognizer(
                translation_config=speech_translation_config,
                audio_config=audio_config
            )
            
            # Collect synthesized audio chunks from direct voice-to-voice translation
            synthesized_audio_chunks = []
            translated_text_parts = []
            recognition_complete = False
            error_occurred = None
            
            def synthesis_callback(evt):
                """Callback for synthesized audio chunks from direct voice-to-voice translation"""
                nonlocal synthesized_audio_chunks
                audio_data = evt.result.audio
                result_reason = evt.result.reason
                
                # Log all synthesis events for debugging
                total_bytes = sum(len(chunk) for chunk in synthesized_audio_chunks)
                logging.info(f"Synthesis event: {len(audio_data)} bytes, reason: {result_reason}, total collected: {len(synthesized_audio_chunks)} chunks, {total_bytes} bytes")
                
                if len(audio_data) > 0:
                    synthesized_audio_chunks.append(audio_data)
                    total_bytes_after = sum(len(chunk) for chunk in synthesized_audio_chunks)
                    logging.info(f"Added audio chunk: {len(audio_data)} bytes (total: {len(synthesized_audio_chunks)} chunks, {total_bytes_after} bytes)")
                elif result_reason == speechsdk.ResultReason.SynthesizingAudioCompleted:
                    logging.info("Synthesis completed - received final empty chunk indicating completion")
                else:
                    logging.warning(f"Synthesis event with 0 bytes, reason: {result_reason}")
            
            def recognized_callback(evt):
                """Callback for recognized and translated speech"""
                nonlocal translated_text_parts
                if evt.result.reason == speechsdk.ResultReason.TranslatedSpeech:
                    recognized_text = evt.result.text
                    if target_language in evt.result.translations:
                        translated_text = evt.result.translations[target_language]
                        translated_text_parts.append(translated_text)
                        logging.info(f"Translated segment: {translated_text[:100]}..." if len(translated_text) > 100 else f"Translated segment: {translated_text}")
                    else:
                        if evt.result.translations:
                            available_lang = list(evt.result.translations.keys())[0]
                            translated_text = evt.result.translations[available_lang]
                            translated_text_parts.append(translated_text)
                            logging.warning(f"Translation not found for {target_language}, using {available_lang}: {translated_text[:100]}...")
                elif evt.result.reason == speechsdk.ResultReason.NoMatch:
                    logging.warning(f"No speech could be recognized: {evt.result.no_match_details}")
            
            def canceled_callback(evt):
                """Callback for canceled recognition"""
                nonlocal error_occurred, recognition_complete
                cancellation = evt.cancellation_details
                
                # EndOfStream is a normal completion when processing files - not an error
                if cancellation.reason == speechsdk.CancellationReason.EndOfStream:
                    logging.info("Audio stream ended - translation completed successfully")
                    recognition_complete = True
                elif cancellation.reason == speechsdk.CancellationReason.Error:
                    error_details = cancellation.error_details or ""
                    
                    # Check if this is a buffer overflow error (can happen with long files or slow processing)
                    if "buffer exceeded" in error_details.lower() or "buffer size" in error_details.lower():
                        # Buffer overflow - this can be retried, but log as warning
                        # If we have some chunks, we could potentially use them, but for voice translation
                        # partial results aren't useful, so we'll treat it as an error for retry
                        error_occurred = f"Buffer overflow error (may be retryable): {error_details}"
                        logging.warning(f"Translation buffer overflow - collected {len(synthesized_audio_chunks)} chunks before error. This may be retried.")
                    else:
                        # Other errors
                        error_occurred = f"Translation error: {error_details}"
                        logging.error(error_occurred)
                    recognition_complete = True
                else:
                    # Other cancellation reasons (e.g., CancelledByUser)
                    logging.warning(f"Translation canceled: {cancellation.reason}")
                    recognition_complete = True
            
            def session_started_callback(evt):
                """Callback when recognition session starts"""
                logging.info(f"Recognition session started: {evt}")
            
            def session_stopped_callback(evt):
                """Callback when recognition session stops"""
                nonlocal recognition_complete
                total_bytes = sum(len(chunk) for chunk in synthesized_audio_chunks)
                logging.info(f"Recognition session stopped. Total collected: {len(synthesized_audio_chunks)} chunks, {total_bytes} bytes")
                recognition_complete = True
            
            # Connect callbacks
            translation_recognizer.session_started.connect(session_started_callback)
            translation_recognizer.synthesizing.connect(synthesis_callback)
            translation_recognizer.recognized.connect(recognized_callback)
            translation_recognizer.canceled.connect(canceled_callback)
            translation_recognizer.session_stopped.connect(session_stopped_callback)
            
            # Perform continuous voice-to-voice translation for long files
            logging.info(f"Starting continuous voice-to-voice translation: {normalized_blob_name}")
            logging.info("Using continuous recognition to process entire file...")
            
            # Start continuous recognition
            translation_recognizer.start_continuous_recognition()
            
            # Wait for recognition to complete (with timeout for very long files)
            max_wait_time = 7200  # 2 hours max wait time
            wait_interval = 1  # Check every second
            elapsed_time = 0
            
            while not recognition_complete and elapsed_time < max_wait_time:
                time.sleep(wait_interval)
                elapsed_time += wait_interval
                if elapsed_time % 30 == 0:  # Log progress every 30 seconds
                    logging.info(f"Translation in progress... ({elapsed_time}s elapsed, {len(synthesized_audio_chunks)} audio chunks, {len(translated_text_parts)} text segments)")
            
            # Stop recognition
            translation_recognizer.stop_continuous_recognition()
            
            # Check for errors
            if error_occurred:
                raise Exception(error_occurred)
            
            if not synthesized_audio_chunks:
                raise Exception("No synthesized audio received from voice-to-voice translation")
            
            # Combine translated text parts
            translated_text = " ".join(translated_text_parts)
            logging.info(f"Translation completed. Total segments: {len(translated_text_parts)}, Total audio chunks: {len(synthesized_audio_chunks)}")
            if translated_text:
                logging.info(f"Full translated text preview: {translated_text[:200]}..." if len(translated_text) > 200 else f"Full translated text: {translated_text}")
            
            # Combine all audio chunks
            total_audio_bytes = sum(len(chunk) for chunk in synthesized_audio_chunks)
            logging.info(f"Combining {len(synthesized_audio_chunks)} audio chunks, total size: {total_audio_bytes} bytes")
            
            combined_audio = b''.join(synthesized_audio_chunks)
            logging.info(f"Combined audio size: {len(combined_audio)} bytes")
            
            # Generate output blob name - preserve source format extension
            base_name = os.path.splitext(os.path.basename(normalized_blob_name))[0]
            # Use source file extension if available, otherwise default to .wav
            output_extension = file_extension if file_extension else '.wav'
            output_blob_name = f"{base_name}_translated_{target_language}{output_extension}"
            
            # Convert WAV output to match source format if different
            if output_extension.lower() != '.wav':
                logging.info(f"Converting audio from WAV to {output_extension} to match source format")
                combined_audio = convert_audio_format(combined_audio, '.wav', output_extension)
            
            # Upload translated audio to blob storage
            output_container = config.get_value("FINAL_OUTPUT_CONTAINER", "silver")
            logging.info(f"Uploading translated audio to {output_container}/{output_blob_name}")
            write_to_blob(output_container, output_blob_name, combined_audio)
            
            return {
                "success": True,
                "original_blob": blob_name,
                "translated_blob": output_blob_name,
                "container": output_container,
                "target_language": target_language,
                "translated_text": translated_text,
                "translated_segments_count": len(translated_text_parts),
                "audio_chunks_count": len(synthesized_audio_chunks),
                "processing_method": "realtime",
                "file_size_mb": file_size_mb
            }
            
        finally:
            # Clean up temporary files
            try:
                if os.path.exists(temp_input_path):
                    os.unlink(temp_input_path)
            except Exception as e:
                logging.warning(f"Error cleaning up temp file: {e}")
                
    except Exception as e:
        logging.error(f"Error during voice-to-voice translation: {e}", exc_info=True)
        raise
