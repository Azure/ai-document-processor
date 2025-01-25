#!/bin/bash

# Ensure environment variables are loaded
eval "$(azd env get-values)"

# Define the JSON structure dynamically
cat <<EOF > local.settings.json
{
  "IsEncrypted": false,
  "Values": {
    "FUNCTIONS_WORKER_RUNTIME": ${FUNCTIONS_WORKER_RUNTIME},
    "AzureWebJobsStorage": ${AzureWebJobsStorage},
    "BLOB_ENDPOINT": ${BLOB_ENDPOINT},
    "OPENAI_API_VERSION": ${OPENAI_API_VERSION},
    "OPENAI_API_BASE": ${OPENAI_API_BASE},
    "OPENAI_MODEL": ${OPENAI_MODEL},
  }
}
EOF

echo "✅ local.settings.json has been created successfully!"