write-host "Post-provisioning script started."

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

# Upload initial prompt file
az storage blob upload --account-name $env:AZURE_STORAGE_ACCOUNT --container-name "prompts" --name prompts.yaml --file ./data/prompts.yaml --auth-mode login

# Note: EventGrid subscription is created in postdeploy hook (scripts/postdeploy.ps1)
# This is because the function code must be deployed first for the webhook validation to succeed.
# See: https://github.com/Azure-Samples/functions-e2e-blob-pdf-to-text for the official pattern.

Write-Host "Post-provision complete. EventGrid subscription will be created after code deployment."