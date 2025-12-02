# Azure Infrastructure Deployment

This directory contains the infrastructure-as-code (Bicep) templates and deployment scripts for the Azure AI Document Processor.

## Files

- `main.bicep` - Main infrastructure template
- `main.parameters.json` - Parameter template (used with azd)
- `deploy.sh` - Standalone deployment script
- `.env.example` - Example environment configuration file

## Prerequisites

1. **Azure CLI** - Install from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli
2. **Azure Subscription** - Active Azure subscription with appropriate permissions
3. **Bash Shell** - Linux, macOS, or WSL on Windows

## Deployment Options

### Option 1: Using the deploy.sh script (Recommended)

#### Quick Start

1. **Copy the example environment file:**
   ```bash
   cp .env.example .env
   ```

2. **Edit `.env` with your values:**
   ```bash
   # Minimum required configuration
   AZURE_SUBSCRIPTION_ID=your-subscription-id
   AZURE_ENV_NAME=dev
   AZURE_LOCATION=eastus2
   AZURE_RESOURCE_GROUP=rg-ai-doc-processor-dev
   AOAI_LOCATION=East US
   ```

3. **Login to Azure:**
   ```bash
   az login
   ```

4. **Run the deployment:**
   ```bash
   ./deploy.sh
   ```

#### Using Environment Variables

You can also set environment variables directly instead of using a `.env` file:

```bash
export AZURE_SUBSCRIPTION_ID=your-subscription-id
export AZURE_ENV_NAME=dev
export AZURE_LOCATION=eastus2
export AZURE_RESOURCE_GROUP=rg-ai-doc-processor-dev
export AOAI_LOCATION="East US"
export FUNCTION_APP_HOST_PLAN=FlexConsumption
export FUNCTION_APP_SKU=FC1

./deploy.sh
```

#### Advanced Configuration

**Network Isolation with VM:**
```bash
export AZURE_NETWORK_ISOLATION=true
export AZURE_DEPLOY_VM=true
export VM_USER_PASSWORD='YourSecureP@ssw0rd!'
./deploy.sh
```

**Using Dedicated Function App Plan:**
```bash
export FUNCTION_APP_HOST_PLAN=Dedicated
export FUNCTION_APP_SKU=S2
./deploy.sh
```

**Reusing Existing Resources:**
```bash
export STORAGE_REUSE=true
export STORAGE_RESOURCE_GROUP_NAME=rg-existing
export STORAGE_NAME=mystorageaccount
./deploy.sh
```

### Option 2: Using Azure Developer CLI (azd)

If you're using the full project with azd:

```bash
# Initialize the environment
azd env new dev

# Set required parameters
azd env set AZURE_LOCATION eastus2
azd env set AOAI_LOCATION "East US"

# Deploy
azd up
```

### Option 3: Direct Azure CLI Deployment

```bash
# Set variables
SUBSCRIPTION_ID=your-subscription-id
ENV_NAME=dev
LOCATION=eastus2
PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)

# Deploy
az deployment sub create \
  --name main-$ENV_NAME-$(date +%Y%m%d-%H%M%S) \
  --location $LOCATION \
  --template-file main.bicep \
  --parameters \
    environmentName=$ENV_NAME \
    location=$LOCATION \
    aoaiLocation="East US" \
    principalId=$PRINCIPAL_ID \
    userPrincipalId=$PRINCIPAL_ID \
    networkIsolation=false \
    deployVM=false \
    deployVPN=false \
    functionAppHostPlan=FlexConsumption \
    functionAppSKU=FC1
```

## Configuration Parameters

### Required Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `AZURE_ENV_NAME` | Environment name | `dev`, `staging`, `prod` |
| `AZURE_LOCATION` | Azure region for most resources | `eastus2`, `westus2` |
| `AOAI_LOCATION` | Azure OpenAI region (see allowed list) | `East US`, `West Europe` |

### Optional Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `AZURE_NETWORK_ISOLATION` | `false` | Enable private endpoints and network isolation |
| `AZURE_DEPLOY_VM` | `false` | Deploy jump box VM for network isolation |
| `AZURE_DEPLOY_VPN` | `false` | Deploy VPN gateway |
| `AI_VISION_ENABLED` | `false` | Enable AI Vision services |
| `AOAI_MULTI_MODAL` | `false` | Enable multi-modal AI capabilities |
| `FUNCTION_APP_HOST_PLAN` | `FlexConsumption` | Function app hosting plan (`FlexConsumption` or `Dedicated`) |
| `FUNCTION_APP_SKU` | `FC1` | Function app SKU |
| `VM_USER_PASSWORD` | - | Password for VM (required if `AZURE_DEPLOY_VM=true`) |

### Allowed Azure OpenAI Locations

- East US
- East US 2
- France Central
- Germany West Central
- Japan East
- Korea Central
- North Central US
- Norway East
- Poland Central
- South Africa North
- South Central US
- South India
- Southeast Asia
- Spain Central
- Sweden Central
- Switzerland North
- Switzerland West
- UAE North
- UK South
- West Europe
- West US
- West US 3

## Deployment Outputs

After successful deployment, the script creates a `deployment-outputs.json` file containing:

- Resource group name
- Function app names and URLs
- Storage account names
- Azure OpenAI endpoint
- Cosmos DB details
- App Configuration name
- Key Vault name

## Resource Reuse

You can reuse existing Azure resources by setting the appropriate reuse flags. This is useful for:

- Sharing resources across environments
- Reducing costs
- Maintaining existing data

Example:
```bash
export COSMOS_DB_REUSE=true
export COSMOS_DB_RESOURCE_GROUP_NAME=rg-shared
export COSMOS_DB_ACCOUNT_NAME=cosmos-shared
export COSMOS_DB_DATABASE_NAME=shared-db
```

## Troubleshooting

### Login Issues
```bash
az login
az account set --subscription <subscription-id>
```

### Permission Errors
Ensure you have:
- Contributor or Owner role on the subscription
- Ability to create role assignments
- Ability to create service principals

### Deployment Validation
```bash
# Validate the template without deploying
az deployment sub validate \
  --location eastus2 \
  --template-file main.bicep \
  --parameters environmentName=dev ...
```

### Check Deployment Status
```bash
# List recent deployments
az deployment sub list --output table

# Show specific deployment
az deployment sub show --name <deployment-name>
```

## Clean Up

To delete all resources:

```bash
# Delete the resource group
az group delete --name <resource-group-name> --yes --no-wait
```

## Support

For issues and questions:
- Check the [troubleshooting guide](../docs/troubleShootingGuide.md)
- Review deployment logs in `postprovision.log`
- Check Azure Portal for deployment status

## License

See [LICENSE](../LICENSE) file in the root directory.
