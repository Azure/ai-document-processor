Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

choco install python311 -y
choco install vscode -y
choco install visualstudio2022enterprise -y
choco install git -y
choco install github-desktop -y
choco install azure-cli -y
choco install azd -y
choco install powershell-core -y
choco install nodejs -y

#install extenstions
Start-Process "C:\Program Files\Microsoft VS Code\bin\code.cmd" -ArgumentList "--install-extension","ms-azuretools.vscode-bicep","--force" -wait

npm install -g @azure/static-web-apps-cli
npm install -g typescript