#!/usr/bin/env bash
set -euo pipefail

eval $(azd env get-values)

cd ./pipeline
func azure functionapp fetch-app-settings $PROCESSING_FUNCTION_APP_NAME --decrypt

func settings decrypt

CONFIG_CONN_STRING=$(az appconfig credential list \
  --name "$APP_CONFIG_NAME" \
  --query "[?name=='Primary'].connectionString" \
  -o tsv)

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

jq \
  --arg CONFIG_CONN_STRING "$CONFIG_CONN_STRING" \
  --arg BLOB_FUNC_CONN_STRING "$BLOB_FUNC_CONN_STRING" \
  --arg BLOB_DATA_STORAGE_CONN_STRING "$BLOB_DATA_STORAGE_CONN_STRING" \
  '
  .Values.AZURE_APPCONFIG_CONNECTION_STRING = $CONFIG_CONN_STRING
  | .Values.AzureWebJobsStorage               = $BLOB_FUNC_CONN_STRING
  | .Values.DataStorage                       = $BLOB_DATA_STORAGE_CONN_STRING
  ' local.settings.json > local.settings.tmp && mv local.settings.tmp local.settings.json


echo "Updated local.settings.json with following values: ${CONFIG_CONN_STRING}, ${BLOB_FUNC_CONN_STRING}, ${BLOB_DATA_STORAGE_CONN_STRING}"