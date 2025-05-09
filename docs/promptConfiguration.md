### Prompt Configuration

There are two options for pulling in a live prompt to be used in your pipeline. These options can be set with the environment variable `PROMPT_FILE`.

1. PROMPT_FILE = 'COSMOS' - This will pull in the prompt from Cosmos DB.
2. PROMPT_FILE = '{path_to_blob_file}' - This will pull in the prompt from the blob storage account. Function reads YAML by default. If the file should be in the `prompts` container. If the the file_name is prompts.yaml, this value should be `prompts.yaml` (do not include the conatiner name in the path)

To use prompts.yaml rather than Cosmos DB, set the environment variable `PROMPT_FILE` to the path of the prompts.yaml file.