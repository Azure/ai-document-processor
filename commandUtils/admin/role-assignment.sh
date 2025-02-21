az cosmosdb sql role assignment create \
  --account-name ${account_name} \
  --resource-group ${resource_group_name} \
  --role-definition-id ${role_definition_id} \
  --principal-id ${principal_id} \
  --scope ${scope}