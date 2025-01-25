#!/bin/sh
echo "Post-provision script started."

echo "Current Path: $(pwd)"
eval "$(azd env get-values)"
echo "Uploading Blob"
az storage blob upload \
  --account-name $AZURE_STORAGE_ACCOUNT \
  --container-name "prompts" \
  --name prompts.yaml \
  --file ./data/prompts.yaml \
  --auth-mode login