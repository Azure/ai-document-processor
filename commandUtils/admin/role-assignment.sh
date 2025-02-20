principal_id='11db3526-9f5a-43c6-b3e4-bde7f47016e9'
role_definition_id='/subscriptions/253f778b-553f-4871-b143-123f314c45c1/resourceGroups/rg-env-2-18/providers/Microsoft.DocumentDB/databaseAccounts/cosmos-ywj5mxscsuces/sqlRoleDefinitions/00000000-0000-0000-0000-000000000002'
resource_group_name='rg-env-2-18'
account_name='cosmos-ywj5mxscsuces'
scope='/subscriptions/253f778b-553f-4871-b143-123f314c45c1/resourceGroups/rg-env-2-18/providers/Microsoft.DocumentDB/databaseAccounts/cosmos-ywj5mxscsuces'

az cosmosdb sql role assignment create \
  --account-name ${account_name} \
  --resource-group ${resource_group_name} \
  --role-definition-id ${role_definition_id} \
  --principal-id ${principal_id} \
  --scope ${scope}