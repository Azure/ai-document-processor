import azure.durable_functions as df

import requests
import time
import logging

from configuration import Configuration

name = "speechToText"
bp = df.Blueprint()


def wait_for_transcription(transcription_url, headers, check_interval=10):
    """Poll the transcription status until it's complete"""
    while True:
        status_response = requests.get(transcription_url, headers=headers)
        status = status_response.json()
        
        current_status = status['status']
        print(f"Status: {current_status}")
        
        if current_status == 'Succeeded':
            print("Transcription completed successfully!")
            return status
        elif current_status == 'Failed':
            print("Transcription failed!")
            print(f"Error: {status.get('properties', {}).get('error', 'Unknown error')}")
            return status
        else:
            print(f"Waiting {check_interval} seconds before checking again...")
            time.sleep(check_interval)


@bp.function_name(name)
@bp.activity_trigger(input_name="blob_input")
def run(blob_input: dict):
    # Parse Arguments
    try: 
        blob_name = blob_input.get('name')
        container = blob_input.get('container')
        blob_uri = blob_input.get('uri')


        config = Configuration()
        credential = config.credential
        token = credential.get_token("https://cognitiveservices.azure.com/.default").token
        
        endpoint = config.get_value("AI_SERVICES_ENDPOINT")
        api_version = "2025-10-15"
        url = f"{endpoint}/speechtotext/transcriptions:submit?api-version={api_version}"

        headers = {
            'Content-Type': 'application/json',
            "Authorization": f"Bearer {token}",
        }

        payload = {
            "displayName": "Transcription",
            "locale": "en-US",
            "contentUrls": [blob_uri], #
            "properties": {
                "wordLevelTimestampsEnabled": False,
                "displayFormWordLevelTimestampsEnabled": False,
                "punctuationMode": "DictatedAndAutomatic",
                "profanityFilterMode": "Masked",
                "timeToLiveHours": 48
            }
        }

        logging.info(f"Submitting transcription request for blob: {blob_name} in container: {container} with payload: {payload}")
        response = requests.post(url, json=payload, headers=headers)
        transcription_url = response.json()['self']

        # Wait for completion
        final_status = wait_for_transcription(transcription_url, headers)

        files_url = final_status['links']['files']

        files_response = requests.get(files_url, headers=headers)
        content_url = files_response.json()['values'][0]['links']['contentUrl']
        content_response = requests.get(content_url).json()
        # content_response.json()
        full_text = content_response['combinedRecognizedPhrases'][0]['display']

    except Exception as e:
        logging.error(f"Error during speech-to-text processing: {e}")
        raise  # Re-raise to allow Durable Functions to retry

    return full_text
