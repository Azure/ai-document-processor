from openai import AzureOpenAI
import os 
import logging
from azure.identity import DefaultAzureCredential, get_bearer_token_provider

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
OPENAI_API_BASE = os.getenv("OPENAI_API_BASE")
OPENAI_MODEL = os.getenv("OPENAI_MODEL")
OPENAI_API_VERSION = os.getenv("OPENAI_API_VERSION")
OPENAI_API_EMBEDDING_MODEL = os.getenv("OPENAI_API_EMBEDDING_MODEL")



def get_embeddings(text):
    credential = DefaultAzureCredential()
    token_provider = get_bearer_token_provider(  
        DefaultAzureCredential(),  
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
    credential = DefaultAzureCredential()
    token_provider = get_bearer_token_provider(  
        DefaultAzureCredential(),  
        "https://cognitiveservices.azure.com/.default"  
    )  

    token = credential.get_token("https://cognitiveservices.azure.com/.default").token

    logging.info(f"Token: {token}")
    
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

