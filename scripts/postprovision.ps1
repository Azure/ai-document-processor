write-host "Post-provisioning script started."

npm install

az storage blob upload --account-name $env:AZURE_STORAGE_ACCOUNT --container-name "prompts" --name prompts.yaml --file ./data/prompts.yaml --auth-mode login
az storage blob upload --account-name $env:AZURE_STORAGE_ACCOUNT --container-name "bronze" --name role_library-3.pdf --file ./data/role_library-3.pdf --auth-mode login

python uploadCosmos.py