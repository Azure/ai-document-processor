az deployment group create --resource-group test-deployment \
  --template-file aoai.bicep \
  --parameters name="aoai-2-15" \
               location="eastus2"