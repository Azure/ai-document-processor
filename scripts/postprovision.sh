#!/bin/sh
echo "Post-provision script started."
resourceGroupName="$AZURE_RESOURCE_GROUP"
functionAppName="$AZURE_FUNCTION_APP_NAME"
storageAccountName="$AZURE_STORAGE_ACCOUNT_NAME"
location="$AZURE_LOCATION"
echo "Current Path: $(pwd)"
echo "Current ls - $(ls -la)"

az storage blob upload \
  --account-name $AZURE_STORAGE_ACCOUNT_NAME \
  --container-name "prompts" \
  --name prompts.yaml \
  --file ./data/prompts.yaml \
  --auth-mode login


# Display the environment variables
echo "Resource Group: $resourceGroupName"
echo "Function App Name: $functionAppName"
echo "Storage Account Name: $storageAccountName"
echo "Location: $location"