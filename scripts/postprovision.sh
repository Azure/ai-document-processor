#!/bin/bash

# Set up logging
LOG_FILE="postprovision.log"
# Redirect stdout and stderr to tee, appending to the log file
exec > >(tee -a "$LOG_FILE") 2> >(tee -a "$LOG_FILE" >&2)

echo "Post-provision script started."

echo "Current Path: $(pwd)"
eval "$(azd env get-values)"
eval "$(azd env get-values | sed 's/^/export /')"
echo "Uploading Blob"

cd frontend
eval "npm install"
cd ..

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


{
  az storage blob upload \
    --account-name $AZURE_STORAGE_ACCOUNT \
    --container-name "bronze" \
    --name role_library-3.pdf \
    --file ./data/role_library-3.pdf \
    --auth-mode login
  echo "Upload of role_library-3.pdf completed successfully to $AZURE_STORAGE_ACCOUNT."
} || {
  echo "file role_library-3.pdf may already exist. Skipping upload"
}



# Check if Static Web App is not deployed, then update .funcignore
if [ "$STATIC_WEB_APP_NAME" = "0" ]; then
  echo "Static Web App is not deployed. Adding static web app configuration to .funcignore."
  # Append desired text; change this text to whatever you need
  echo -e "\napp*" >> .funcignore

  echo "No frontend deployed. Removing webbackend service from azure.yaml..."
  sed -i '/^  webbackend:/,/^hooks:/{ /^hooks:/!d; }' azure.yaml
else

  echo "Frontend deployed. Setting up Cosmos DB..."
  # Establish a Python virtual environment and install dependencies
  echo "Setting up Python environment..."
  python -m venv .venv
  source .venv/bin/activate
  pip install -r ./web-backend/requirements.txt

  echo "Running uploadCosmos.py..."
  python scripts/uploadCosmos.py

  echo "Post-provision script finished."

  echo "Checking if Static Web App is not deployed..."
  echo "Static Web App Name: $STATIC_WEB_APP_NAME"

  echo "Updating web backend function app env variables with processing function app name..."
  {
    PROCESSING_FUNCTION_APP_NAME=$(az functionapp show --name $PROCESSING_FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP --query "name" -o tsv)

    # Update the web backend function app with the environment variable
    az functionapp config appsettings set --name $WEB_BACKEND_FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP --settings PROCESSING_FUNCTION_APP_NAME=$PROCESSING_FUNCTION_APP_NAME
  } || {
    echo "Error getting the processing function app name and updating the web backend function app"
  }
fi

