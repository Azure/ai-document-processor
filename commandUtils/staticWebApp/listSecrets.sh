
az staticwebapp secrets list --name ${STATIC_WEB_APP_NAME} --resource-group ${AZURE_RESOURCE_GROUP} --query "properties.apiKey"