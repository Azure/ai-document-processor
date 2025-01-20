#!/bin/bash

# Ensure environment variables are loaded
eval "$(azd env get-values)"

# Define the JSON structure dynamically
cat <<EOF > local.settings.json
{
  "IsEncrypted": false,
  "Values": {
    "AZURE_ENV_NAME": "$AZURE_ENV_NAME",
    "AZURE_LOCATION": "$AZURE_LOCATION",
    "AZURE_RESOURCE_GROUP": "$AZURE_RESOURCE_GROUP",
    "AZURE_STORAGE_ACCOUNT": "$AZURE_STORAGE_ACCOUNT",
    "AZURE_SUBSCRIPTION_ID": "$AZURE_SUBSCRIPTION_ID",
    "FUNCTION_APP_NAME": "$FUNCTION_APP_NAME",
    "FUNCTION_URL": "$FUNCTION_URL",
    "RESOURCE_GROUP": "$RESOURCE_GROUP",
    "functionUrl": "$functionUrl"
  }
}
EOF

echo "✅ local.settings.json has been created successfully!"