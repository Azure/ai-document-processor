# Script to fix the soft-deleted Key Vault issue
# Run this script to purge the deleted Key Vault

$keyVaultName = "kv-la5nkiw63xww4"
$resourceGroupName = "rg-voice2voice_T"

Write-Host "Checking for deleted Key Vault: $keyVaultName" -ForegroundColor Yellow

# List all deleted Key Vaults
$deletedVaults = az keyvault list-deleted --query "[?name=='$keyVaultName']" --output json | ConvertFrom-Json

if ($deletedVaults) {
    Write-Host "Found deleted Key Vault. Purging..." -ForegroundColor Yellow
    
    # Purge the deleted Key Vault (this permanently deletes it)
    az keyvault purge --name $keyVaultName
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Key Vault purged successfully. You can now run 'azd up' again." -ForegroundColor Green
    } else {
        Write-Host "Failed to purge Key Vault. Trying recovery instead..." -ForegroundColor Red
        
        # Alternative: Recover the Key Vault instead of purging
        Write-Host "Recovering Key Vault..." -ForegroundColor Yellow
        az keyvault recover --name $keyVaultName --location "East US 2"
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Key Vault recovered. You may need to delete it normally before redeploying." -ForegroundColor Green
        }
    }
} else {
    Write-Host "No deleted Key Vault found with that name. It may have already been purged." -ForegroundColor Green
    Write-Host "You can try running 'azd up' again." -ForegroundColor Green
}
