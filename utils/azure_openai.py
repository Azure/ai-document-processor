from openai import AzureOpenAI
import os 

OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")
OPENAI_API_BASE = os.getenv("OPENAI_API_BASE")
OPENAI_API_VERSION = os.getenv("OPENAI_API_VERSION")
OPENAI_API_EMBEDDING_MODEL = os.getenv("OPENAI_API_EMBEDDING_MODEL")
def get_embeddings(text):

    openai_client = AzureOpenAI(
            api_key =   OPENAI_API_KEY,
            api_version = OPENAI_API_VERSION,
            azure_endpoint =OPENAI_API_BASE
            )
    
    embedding = openai_client.embeddings.create(
                 input = text,
                 model= OPENAI_API_EMBEDDING_MODEL
             ).data[0].embedding
    
    return embedding


def run_prompt(prompt,system_prompt):

    openai_client = AzureOpenAI(
            api_key =   OPENAI_API_KEY,
            api_version = OPENAI_API_VERSION,
            azure_endpoint =OPENAI_API_BASE
            )
    
    response = openai_client.chat.completions.create(
        model="gpt-4o",
        messages=[{ "role": "system", "content": system_prompt},
              {"role":"user","content":prompt}])
    
    return response.choices[0].message.content

