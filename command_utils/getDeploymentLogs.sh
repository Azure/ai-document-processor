eval "$(azd env get-values)"
echo $FUNCTION_APP_NAME

az functionapp log deployment show --name $FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP --output table
# # az functionapp log deployment list --name functionapp-env-1-10-f2edifarji5iq --resource-group llm-processing-1-10