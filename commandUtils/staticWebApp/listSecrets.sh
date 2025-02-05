STATIC_WEB_APP_NAME="static-env-2-4-v3-76he5amidpqfk"
AZURE_RESOURCE_GROUP="rg-env-2-4-v3"

az staticwebapp secrets list --name ${STATIC_WEB_APP_NAME} --resource-group ${AZURE_RESOURCE_GROUP} --query "properties.apiKey"