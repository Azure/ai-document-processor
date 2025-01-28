## Instructions

1. Fork repo to your GH account
2. Clone your forked repo
3. To deploy bicep template run:
- azd auth login
- az login
- azd up
- Enter your forked GH repo link `https://github.com/{your_user_name}/llm-doc-processing`
- Enter your User Principal ID when prompted
- To get your User principal ID run `az ad signed-in-user show --query id -o tsv`

2. After deployment is complete configure Static Web App
   - Navigate to "Configuration"
   - Switch "Deployment Authorization Policy" to Github
   - Enter "./webapp/frontend/" in the App Location field
   - Ensure the Api Location is empty
   - Enter "dist" in the App artifact location
   - Click Apply
   - GH Actions workflow should be created in your GH repo
