# az functionapp function show --name functionapp-env-1-10-f2edifarji5iq --resource-group llm-processing-1-10 --function-name process_uploads --query properties.config.disabled
az functionapp function list --name $FUNCTION_URL --resource-group $RESOURCE_GROUP --query "[].{Name:name}" --output table
