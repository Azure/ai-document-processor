eval $(azd env get-values)

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
swa deploy --env Production -d "${token}"