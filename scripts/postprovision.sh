#!/bin/sh
echo "Post-provision script started."

echo "Current Path: $(pwd)"
eval "$(azd env get-values)"
echo "Uploading Blob"

{
  az storage blob upload \
    --account-name $AZURE_STORAGE_ACCOUNT \
    --container-name "prompts" \
    --name prompts.yaml \
    --file ./data/prompts.yaml \
    --auth-mode login
  echo "Upload completed successfully."
} || {
  echo "file prompts.yaml may already exist. Skipping upload"
}

echo "Post-provision script finished."