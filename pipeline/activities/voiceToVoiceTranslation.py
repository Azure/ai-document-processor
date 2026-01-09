import azure.durable_functions as df
import azure.cognitiveservices.speech as speechsdk
import logging
import tempfile
import os
from pipelineUtils.blob_functions import get_blob_content, write_to_blob
from configuration import Configuration

name = "voiceToVoiceTranslation"
bp = df.Blueprint()

def normalize_blob_name(container: str, raw_name: str) -> str:
    """Strip container prefix if included in the name."""
    if raw_name.startswith(container + "/"):
        return raw_name[len(container) + 1:]
    return raw_name

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
        
        # Normalize blob name (strip container prefix if present)
        normalized_blob_name = normalize_blob_name(container, blob_name)
        
        # Download audio file from blob storage
        logging.info(f"Downloading audio file: {normalized_blob_name}")
        audio_content = get_blob_content(container, normalized_blob_name)
        
        # Create temporary file for input audio
        with tempfile.NamedTemporaryFile(delete=False, suffix='.wav') as temp_input:
            temp_input.write(audio_content)
            temp_input_path = temp_input.name
        
        try:
            # Extract region from endpoint or config
            try:
                if ".api.cognitive.microsoft.com" in speech_endpoint:
                    region = speech_endpoint.split("//")[1].split(".")[0]
                else:
                    region = config.get_value("SPEECH_SERVICE_REGION", "eastus")
            except Exception:
                region = config.get_value("SPEECH_SERVICE_REGION", "eastus")
            
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
                voice_map = {
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
                voice_name = voice_map.get(target_language, f"{target_language}-Neural")
                speech_translation_config.voice_name = voice_name
                logging.info(f"Using neural voice: {voice_name} for language: {target_language}")
            
            # Configure audio input from file
            audio_config = speechsdk.audio.AudioConfig(filename=temp_input_path)
            
            # Create translation recognizer
            translation_recognizer = speechsdk.translation.TranslationRecognizer(
                translation_config=speech_translation_config,
                audio_config=audio_config
            )
            
            # Collect synthesized audio chunks from direct voice-to-voice translation
            synthesized_audio_chunks = []
            translated_text = ""
            
            def synthesis_callback(evt):
                """Callback for synthesized audio chunks from direct voice-to-voice translation"""
                nonlocal synthesized_audio_chunks
                audio_data = evt.result.audio
                if len(audio_data) > 0:
                    synthesized_audio_chunks.append(audio_data)
            
            translation_recognizer.synthesizing.connect(synthesis_callback)
            
            # Perform direct voice-to-voice translation
            logging.info(f"Starting voice-to-voice translation: {normalized_blob_name}")
            translation_result = translation_recognizer.recognize_once()
            
            # Check result
            if translation_result.reason == speechsdk.ResultReason.TranslatedSpeech:
                logging.info(f"Recognized: {translation_result.text}")
                if target_language in translation_result.translations:
                    translated_text = translation_result.translations[target_language]
                    logging.info(f"Translated to '{target_language}': {translated_text}")
                else:
                    if translation_result.translations:
                        available_lang = list(translation_result.translations.keys())[0]
                        translated_text = translation_result.translations[available_lang]
                        logging.warning(f"Translation not found for {target_language}, using {available_lang}")
            else:
                error_msg = f"Voice-to-voice translation failed: {translation_result.reason}"
                if translation_result.reason == speechsdk.ResultReason.Canceled:
                    cancellation = translation_result.cancellation_details
                    error_msg += f" - {cancellation.reason}: {cancellation.error_details}"
                raise Exception(error_msg)
            
            # Combine all audio chunks
            if not synthesized_audio_chunks:
                raise Exception("No synthesized audio received from voice-to-voice translation")
            
            combined_audio = b''.join(synthesized_audio_chunks)
            
            # Generate output blob name
            base_name = os.path.splitext(os.path.basename(normalized_blob_name))[0]
            output_blob_name = f"{base_name}_translated_{target_language}.wav"
            
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
                "translated_text": translation_result.translations.get(target_language, "") if hasattr(translation_result, 'translations') else ""
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
