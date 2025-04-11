#!/bin/bash

eval "$(azd env get-values)"
eval "$(azd env get-values | sed 's/^/export /')"

# Get the name of the processing function app
{
  PROCESSING_FUNCTION_APP_NAME=$(az functionapp show --name $PROCESSING_FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP --query "name" -o tsv)

  # Update the web backend function app with the environment variable
  az functionapp config appsettings set --name $WEB_BACKEND_FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP --settings PROCESSING_FUNCTION_APP_NAME=$PROCESSING_FUNCTION_APP_NAME
} || {
  echo "Error getting the processing function app name and updating the web backend function app"
}


# Update CORS settings