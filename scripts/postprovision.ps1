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

# Upload initial blob and prompt file
az storage blob upload --account-name $env:AZURE_STORAGE_ACCOUNT --container-name "prompts" --name prompts.yaml --file ./data/prompts.yaml --auth-mode login
az storage blob upload --account-name $env:AZURE_STORAGE_ACCOUNT --container-name "bronze" --name role_library-3.pdf --file ./data/role_library-3.pdf --auth-mode login