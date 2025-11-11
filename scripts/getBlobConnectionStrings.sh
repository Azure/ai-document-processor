set -euo pipefail

eval $(azd env get-values)

cd ./pipeline
# func azure functionapp fetch-app-settings $PROCESSING_FUNCTION_APP_NAME --decrypt

BLOB_FUNC_CONN_STRING=$(az storage account show-connection-string \
  --name $AZURE_STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --query connectionString \
  -o tsv)

BLOB_DATA_STORAGE_CONN_STRING=$(az storage account show-connection-string \
  --name $AZURE_STORAGE_ACCOUNT \
  --resource-group $RESOURCE_GROUP \
  --query connectionString \
  -o tsv)

echo "Blob connection string: $BLOB_FUNC_CONN_STRING"
echo "Data Storage connection string: $BLOB_DATA_STORAGE_CONN_STRING"
