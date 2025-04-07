from openai import AzureOpenAI
import os 
import logging
from azure.identity import DefaultAzureCredential, get_bearer_token_provider

from configuration import Configuration
config = Configuration()

OPENAI_API_KEY = config.get_value("OPENAI_API_KEY")
OPENAI_API_BASE = config.get_value("OPENAI_API_BASE")
OPENAI_MODEL = config.get_value("OPENAI_MODEL")
OPENAI_API_VERSION = config.get_value("OPENAI_API_VERSION")
OPENAI_API_EMBEDDING_MODEL = config.get_value("OPENAI_API_EMBEDDING_MODEL")

def get_embeddings(text):
    credential = config.credential
    token_provider = get_bearer_token_provider(  
        config.credential,  
        "https://cognitiveservices.azure.com/.default"  
    )  

    token = credential.get_token("https://cognitiveservices.azure.com/.default").token
    openai_client = AzureOpenAI(
            azure_ad_token=token,
            api_version = OPENAI_API_VERSION,
            azure_endpoint =OPENAI_API_BASE
            )
    
    embedding = openai_client.embeddings.create(
                 input = text,
                 model= OPENAI_API_EMBEDDING_MODEL
             ).data[0].embedding
    
    return embedding


def run_prompt(prompt,system_prompt):
    credential = config.credential
    token_provider = get_bearer_token_provider(  
        credential,  
        "https://cognitiveservices.azure.com/.default"  
    )  

    token = credential.get_token("https://cognitiveservices.azure.com/.default").token
    
    openai_client = AzureOpenAI(
        azure_ad_token=token,
        api_version = OPENAI_API_VERSION,
        azure_endpoint =OPENAI_API_BASE
    )

    
    response = openai_client.chat.completions.create(
        model=OPENAI_MODEL,
        messages=[{ "role": "system", "content": system_prompt},
              {"role":"user","content":prompt}])
    
    return response.choices[0].message.content

