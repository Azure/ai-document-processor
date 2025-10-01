#!/usr/bin/env bash
set -euo pipefail

eval $(azd env get-values)

cd ./pipeline
func azure functionapp fetch-app-settings $PROCESSING_FUNCTION_APP_NAME --decrypt

func settings decrypt

CONN_STRING=$(az appconfig credential list \
  --name "$APP_CONFIG_NAME" \
  --query "[?name=='Primary'].connectionString" \
  -o tsv)

jq --arg conn "$CONN_STRING" '
  .Values.AZURE_APPCONFIG_CONNECTION_STRING = $conn
  | .Values.AzureWebJobsStorage = "UseDevelopmentStorage=true"
  | .Values.DataStorage = "UseDevelopmentStorage=true"
  | .Values.blob_uploads = "UseDevelopmentStorage=true"
  | .Values.AZURE_FUNCTIONS_ENVIRONMENT = "Development"
' local.settings.json > local.settings.tmp && mv local.settings.tmp local.settings.json