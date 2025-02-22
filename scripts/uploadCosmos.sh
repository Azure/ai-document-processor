#!/bin/bash
eval "$(azd env get-values)"

# Define variables from environment (these can be overridden below)
accountName="${COSMOS_DB_ACCOUNT_NAME}"
databaseName="${COSMOS_DB_PROMPTS_DB}"
promptsContainer="${COSMOS_DB_PROMPTS_CONTAINER}"
configContainer="${COSMOS_DB_CONFIG_CONTAINER}"
resourceGroup="${AZURE_RESOURCE_GROUP}"
endpoint="${COSMOS_DB_URI}"

# Delete before push (override env values for testing)
accountName="cosmos-qylnraw6fs7hk"
databaseName="openaiPromptsDB"
promptsContainer="promptscontainer"
configContainer="config"

# Get the Cosmos DB endpoint using Azure CLI
endpoint=$(az cosmosdb show \
  --name "$accountName" \
  --resource-group "$resourceGroup" \
  --query documentEndpoint \
  --output tsv)

# Instead of using keys, get an Azure AD access token for Cosmos DB.
# The resource URI for Cosmos DB is "https://cosmos.azure.com/"
token=$(az account get-access-token \
  --resource "https://cosmos.azure.com/" \
  --query accessToken \
  --output tsv)

# Specify the paths to your JSON files
promptsPath="./data/promptscontainer.json"
configPath="./data/config.json"

# Check if the JSON files exist
if [ ! -f "$promptsPath" ]; then
  echo "Prompts JSON file not found: $promptsPath"
  exit 1
fi

if [ ! -f "$configPath" ]; then
  echo "Config JSON file not found: $configPath"
  exit 1
fi

# Get the current date in GMT format for the x-ms-date header
xmsdate=$(date -u '+%a, %d %b %Y %H:%M:%S GMT')

# Loop through each item in the prompts JSON file and upload to Cosmos DB
# Using a while-read loop ensures that JSON objects with spaces or special characters are handled correctly.
while read -r item; do
  curl -X POST "$endpoint/dbs/$databaseName/colls/$promptsContainer/docs" \
    -H "Authorization: Bearer $token" \
    -H "x-ms-date: $xmsdate" \
    -H "x-ms-version: 2018-12-31" \
    -H "Content-Type: application/json" \
    -d "$item"
done < <(jq -c '.[]' < "$promptsPath")
