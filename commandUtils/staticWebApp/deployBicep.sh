az deployment group create --resource-group rg-env-2-3-v2 \
  --template-file staticWebapp.bicep \
  --parameters staticWebAppName="testStatic" \
               functionAppResourceId="/subscriptions/253f778b-553f-4871-b143-123f314c45c1/resourceGroups/rg-env-2-3-v2/providers/Microsoft.Web/sites/functionapp-env-2-3-v2-vmjpwdskymigq" \
               user_gh_url="https://github.com/markremmey/ai-document-processor-v1" \
               location="eastus2"


