#!/bin/bash
echo "Post-provision script started."

echo "Current Path: $(pwd)"
eval "$(azd env get-values)"
eval "$(azd env get-values | sed 's/^/export /')"
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


{
  az storage blob upload \
    --account-name $AZURE_STORAGE_ACCOUNT \
    --container-name "bronze" \
    --name role_library-3.pdf \
    --file ./data/role_library-3.pdf \
    --auth-mode login
  echo "Upload completed successfully."
} || {
  echo "file role_library-3.pdf may already exist. Skipping upload"
}


# Establish a Python virtual environment and install dependencies
echo "Setting up Python environment..."
python -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

echo "Running uploadCosmos.py..."
python scripts/uploadCosmos.py

echo "Post-provision script finished."

echo "Checking if Static Web App is not deployed..."
echo "Static Web App Name: $STATIC_WEB_APP_NAME"
# Check if Static Web App is not deployed, then update .funcignore
if [ "$STATIC_WEB_APP_NAME" = "0" ]; then
  echo "Static Web App is not deployed. Adding static web app configuration to .funcignore."
  # Append desired text; change this text to whatever you need
  echo -e "\napp*" >> .funcignore
fi

echo "Post-provision script finished."