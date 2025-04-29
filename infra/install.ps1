Param (
  [Parameter(Mandatory = $true)]
  [string]
  $azureTenantID,

  [string]
  $azureSubscriptionID,

  [string]
  $AzureResourceGroupName,

  [string]
  $AzdEnvName
)

Start-Transcript -Path C:\WindowsAzure\Logs\CMFAI_CustomScriptExtension.txt -Append

[Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls
[Net.ServicePointManager]::SecurityProtocol = "tls12, tls11, tls" 

Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

choco upgrade vscode -y
choco upgrade azure-cli -y
choco upgrade git -y
choco upgrade nodejs -y

choco install python311 -y
#choco install visualstudio2022enterprise -y
choco install azd -y
choco install powershell-core -y
choco install github-desktop -y

#install extenstions
Start-Process "C:\Program Files\Microsoft VS Code\bin\code.cmd" -ArgumentList "--install-extension","ms-azuretools.vscode-bicep","--force" -wait

wsl --update

mkdir C:\github
cd C:\github
git clone https://github.com/givenscj/ai-document-processor
#git checkout cjg-zta
cd ai-document-processor

az login --tenant $azureTenantID
azd auth login --tenant-id $azureTenantID

npm install -g @azure/static-web-apps-cli
npm install -g typescript

azd init $AzdEnvName

#restart the VM
shutdown -r

Stop-Transcript