echo "Setting static web app environment variables"
echo "Current Path: $(pwd)"

eval "$(azd env get-values)"

echo "$AZURE_STATIC_WEB_APP_NAME"
echo "$AZURE_RESOURCE_GROUP"
echo "$AZURE_STORAGE_ACCOUNT"
echo "$FUNCTION_APP_NAME"
echo "$PROMPT_FILE"
echo "$FUNCTION_URL"

az staticwebapp appsettings set \
  --name $AZURE_STATIC_WEB_APP_NAME \
  --resource-group $AZURE_RESOURCE_GROUP \
  --setting-names STORAGE_ACCOUNT_NAME=$AZURE_STORAGE_ACCOUNT FUNCTION_APP_NAME=$FUNCTION_APP_NAME PROMPT_FILE=$PROMPT_FILE FUNCTION_URL=$FUNCTION_URL