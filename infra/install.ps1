Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

choco upgrade vscode -y
choco upgrade azure-cli -y

choco install python311 -y
#choco install visualstudio2022enterprise -y
choco install git -y
choco install github-desktop -y
choco install azd -y
choco install powershell-core -y
choco install nodejs -y

#install extenstions
Start-Process "C:\Program Files\Microsoft VS Code\bin\code.cmd" -ArgumentList "--install-extension","ms-azuretools.vscode-bicep","--force" -wait

wsl --update

mkdir C:\github
cd C:\github
git clone https://github.com/givenscj/ai-document-processor
cd ai-document-processor

$tenantId = "your_tenant_id"
az login --use-device-code --tenant $tenantId
azd auth login --tenant-id $tenantId

npm install -g @azure/static-web-apps-cli
npm install -g typescript