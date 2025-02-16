az deployment group create --resource-group test-deployment \
  --template-file functionApp.bicep \
  --parameters appName="testfunctionRemmey" \
               location="eastus2" \
               storageAccountName="stenvremmey" \
               aoaiEndpoint="aoai-2-15.openai.azure.com"