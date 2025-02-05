eval $(azd env get-values)
STATIC_WEB_APP_NAME="static-test"
AZURE_RESOURCE_GROUP="rg-env-2-4-v3"

az login --use-device-code

token=$(az staticwebapp secrets list \
  --name "${STATIC_WEB_APP_NAME}" \
  --resource-group "${AZURE_RESOURCE_GROUP}" \
  --query "properties.apiKey" \
  -o tsv)
echo "token: ${token}"
cd frontend
swa init
swa build
swa deploy -d "${token}"