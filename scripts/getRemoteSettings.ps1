#!/usr/bin/env pwsh
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Write-Host "Loading remote settings into local.settings.json from Azure resources..."
# Load azd environment values (emulates: eval $(azd env get-values))
azd env get-values | ForEach-Object {
    if ($_ -match '^(?<key>[^=]+)=(?<val>.*)$') {
        $k = $matches.key.Trim()
        $v = $matches.val

        # Remove exactly one outer pair of double quotes if present
        if ($v.Length -ge 2 -and $v.StartsWith('"') -and $v.EndsWith('"')) {
            $v = $v.Substring(1, $v.Length - 2)
            # Unescape any embedded \" (azd usually doesn’t emit these, but safe)
            $v = $v -replace '\\"','"'
        }

        [Environment]::SetEnvironmentVariable($k, $v)
        Set-Variable -Name $k -Value $v -Scope Script -Force
    }
}

# (Optional) Quick debug echo – comment out when stable
Write-Host "PROCESSING_FUNCTION_APP_NAME => '$($env:PROCESSING_FUNCTION_APP_NAME)'" 
Write-Host "APP_CONFIG_NAME              => '$($env:APP_CONFIG_NAME)'" 

# Move into pipeline directory relative to script location
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location (Join-Path $scriptDir '../pipeline')

if (-not $env:PROCESSING_FUNCTION_APP_NAME) { throw "PROCESSING_FUNCTION_APP_NAME not set." }

func azure functionapp fetch-app-settings $env:PROCESSING_FUNCTION_APP_NAME --decrypt
func settings decrypt

# Get App Configuration primary connection string
if (-not $env:APP_CONFIG_NAME) {
    throw "APP_CONFIG_NAME not set."
}
$connString = az appconfig credential list `
  --name $env:APP_CONFIG_NAME `
  --query "[?name=='Primary'].connectionString" `
  -o tsv

if (-not $connString) {
    throw "Failed to retrieve App Configuration connection string."
}

# Update local.settings.json (replace jq operation)
$localSettingsPath = "local.settings.json"
if (-not (Test-Path $localSettingsPath)) {
    throw "File not found: $localSettingsPath"
}

$json = Get-Content $localSettingsPath -Raw | ConvertFrom-Json

if (-not $json.Values) {
    # Ensure Values object exists
    $json | Add-Member -NotePropertyName Values -NotePropertyValue (@{}) -Force
}

$json.Values.AZURE_APPCONFIG_CONNECTION_STRING = $connString

# Write back (preserve UTF-8)
$json | ConvertTo-Json -Depth 10 | Set-Content $localSettingsPath -Encoding UTF8
Write-Host "Updated AZURE_APPCONFIG_CONNECTION_STRING in local.settings.json"