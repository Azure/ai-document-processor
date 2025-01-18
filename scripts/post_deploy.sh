#!/usr/bin/env bash

# Load the environment values from azd:
# (You can also parse them directly from .azure/<env>/.env
# or use 'azd env get-values --output json | jq' for JSON)
eval "$(azd env get-values --shell bash)"

# Now, $functionAppName, $blobEndpoint, etc. should be available
# in the script’s environment if they were mapped in azure.yaml.

# --------------------------------------------------------------------------------
# 1. Write to local.settings.json
# --------------------------------------------------------------------------------

LOCAL_SETTINGS_FILE="./local.settings.json"

# If local.settings.json doesn’t exist yet, create a minimal skeleton:
if [ ! -f "$LOCAL_SETTINGS_FILE" ]; then
  cat <<EOF > "$LOCAL_SETTINGS_FILE"
{
  "IsEncrypted": false,
  "Values": {}
}
EOF
fi

# Use 'jq' to update local.settings.json. For example:
jq --arg blobEndpoint "$blobEndpoint" \
   --arg functionAppName "$functionAppName" \
   '
   .Values.BLOB_ENDPOINT = $blobEndpoint
   | .Values.FUNCTION_APP_NAME = $functionAppName
   ' \
   "$LOCAL_SETTINGS_FILE" > "$LOCAL_SETTINGS_FILE.tmp" && mv "$LOCAL_SETTINGS_FILE.tmp" "$LOCAL_SETTINGS_FILE"

echo "Updated $LOCAL_SETTINGS_FILE with new values."

# --------------------------------------------------------------------------------
# 2. Export environment variables to the current shell
# --------------------------------------------------------------------------------

export BLOB_ENDPOINT="$blobEndpoint"
export FUNCTION_APP_NAME="$functionAppName"

# Echo them just for clarity
echo "Exported BLOB_ENDPOINT=$BLOB_ENDPOINT"
echo "Exported FUNCTION_APP_NAME=$FUNCTION_APP_NAME"
