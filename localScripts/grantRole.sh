eval $(azd env get-values)

functionAppId=$(az functionapp identity show --name $PROCESSING_FUNCTION_APP_NAME --resource-group $RESOURCE_GROUP | jq -r '.userAssignedIdentities[] | .principalId')
echo "Function App ID: $functionAppId"
scope=$(az group show --name $RESOURCE_GROUP --resource-group $RESOURCE_GROUP | jq -r '.id')
echo "Scope: $scope"
# Example: grant App Config Data Reader
echo "Granting App Configuration Data Reader role to Function App..."
az role assignment create \
  --assignee-object-id $functionAppId \
  --role "App Configuration Data Reader" \
  --scope $scope

echo "Granting Key Vault Secrets User role to Function App..."
# Example: grant Key Vault Secrets User (RBAC model)
az role assignment create \
  --assignee-object-id $functionAppId \
  --role "Key Vault Secrets User" \
  --scope $scope

# Grant Storage Blob Data Owner role to Function App
echo "Granting Storage Blob Data Owner role to Function App..."
az role assignment create \
  --assignee-object-id $functionAppId \
  --role "Storage Blob Data Owner" \
  --scope $scope

# Grant Storage Queue Data Contributor role to Function App
echo "Granting Storage Queue Data Contributor role to Function App..."
az role assignment create \
  --assignee-object-id $functionAppId \
  --role "Storage Queue Data Contributor" \
  --scope $scope

# Grant Storage Table Data Contributor role to Function App
echo "Granting Storage Table Data Contributor role to Function App..."
az role assignment create \
  --assignee-object-id $functionAppId \
  --role "Storage Table Data Contributor" \
  --scope $scope