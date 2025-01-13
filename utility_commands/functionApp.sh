# az functionapp function show --name functionapp-env-1-10-f2edifarji5iq --resource-group llm-processing-1-10 --function-name process_uploads --query properties.config.disabled
az functionapp function list --name functionapp-new-env-1-12-an2sevgsxcrdi --resource-group llm-doc-1-12 --query "[].{Name:name}" --output table
