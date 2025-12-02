#!/bin/bash

# Set up logging
LOG_FILE="postdeploy.log"
# Redirect stdout and stderr to tee, appending to the log file
exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)

echo "Post-provision script started."

echo "Current Path: $(pwd)"
eval "$(azd env get-values)"
eval "$(azd env get-values | sed 's/^/export /')"
echo "Uploading Blob to Azure Storage Account: $AZURE_STORAGE_ACCOUNT"

{
  az storage blob upload \
    --account-name $AZURE_STORAGE_ACCOUNT \
    --container-name "prompts" \
    --name prompts.yaml \
    --file ./data/prompts.yaml \
    --auth-mode login
  echo "Upload of prompts.yaml completed successfully to $AZURE_STORAGE_ACCOUNT."
} || {
  echo "file prompts.yaml may already exist. Skipping upload"
}