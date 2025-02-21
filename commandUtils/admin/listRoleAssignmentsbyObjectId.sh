az role assignment list \
  --assignee ${principal_id} \
  --scope ${resource_id} \
  --query "[].{Role:roleDefinitionName, Scope:scope}" \
  -o table
