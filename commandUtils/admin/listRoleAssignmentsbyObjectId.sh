az role assignment list \
  --assignee 352b6f9b-ccc6-474d-8326-33e1a04eeeb7 \
  --scope /subscriptions/58360d6a-cbcb-4991-83ad-0466b411a59e/resourceGroups/test-deployment/providers/Microsoft.Storage/storageAccounts/stenvremmey \
  --query "[].{Role:roleDefinitionName, Scope:scope}" \
  -o table
