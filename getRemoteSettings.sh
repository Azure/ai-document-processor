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

jq --arg conn "$CONN_STRING" \
   '.Values.APP_CONFIGURATION_CONNECTION_STRING = $conn' \
   local.settings.json > local.settings.tmp && mv local.settings.tmp local.settings.json

