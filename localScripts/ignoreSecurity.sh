eval $(azd env get-values)

RESOURCE_GROUP=$(azd env get-value RESOURCE_GROUP)
STORAGE_ACCOUNT=$(azd env get-value AZURE_STORAGE_ACCOUNT)
PROCESSING_STORAGE_ACCOUNT=$(azd env get-value FUNCTION_APP_STORAGE_NAME)
KEYVAULT_NAME=$(azd env get-value KEY_VAULT_NAME)

PROCECSSING_STORAGE_ACCOUNT='stv6zimp7cxt2mkfnproc'
KEYVAULT_NAME='kv-v6zimp7cxt2mk'

TAG_KEY="SecurityControl"
TAG_VALUE="Ignore"
echo "Getting resource IDs..."
STORAGE_ID=$(az storage account show \
    -g "$RESOURCE_GROUP" \
    -n "$STORAGE_ACCOUNT" | jq -r '.id')

KEYVAULT_ID=$(az keyvault show \
    -g "$RESOURCE_GROUP" \
    -n "$KEYVAULT_NAME" | jq -r '.id')

echo "Tagging Storage Account..."
az tag create --resource-id "$STORAGE_ID" \
    --tags "$TAG_KEY=$TAG_VALUE"

echo "Tagging Key Vault..."
az tag create --resource-id "$KEYVAULT_ID" \
    --tags "$TAG_KEY=$TAG_VALUE"