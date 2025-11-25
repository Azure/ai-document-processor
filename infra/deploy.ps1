##############################################################################
# Azure Bicep Deployment Script (PowerShell)
# This script deploys the main.bicep infrastructure template
##############################################################################

#Requires -Version 7.0

[CmdletBinding()]
param()

# Stop on errors
$ErrorActionPreference = 'Stop'

##############################################################################
# Logging Functions
##############################################################################

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-Success {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

##############################################################################
# Script Configuration
##############################################################################

$ScriptDir = $PSScriptRoot
$BicepFile = Join-Path $ScriptDir "main.bicep"
$ParamsFile = Join-Path $ScriptDir "main.parameters.json"

##############################################################################
# Configuration - Set these variables or environment variables
##############################################################################

# Required parameters
$AzureSubscriptionId = if ($env:AZURE_SUBSCRIPTION_ID) { $env:AZURE_SUBSCRIPTION_ID } else { "" }
$AzureEnvName = if ($env:AZURE_ENV_NAME) { $env:AZURE_ENV_NAME } else { "dev" }
$AzureLocation = if ($env:AZURE_LOCATION) { $env:AZURE_LOCATION } else { "eastus2" }
$AzureResourceGroup = if ($env:AZURE_RESOURCE_GROUP) { $env:AZURE_RESOURCE_GROUP } else { "" }

# Azure OpenAI location (must be one of the allowed locations)
$AoaiLocation = if ($env:AOAI_LOCATION) { $env:AOAI_LOCATION } else { "East US" }

# Network and VM settings
$AzureNetworkIsolation = if ($env:AZURE_NETWORK_ISOLATION) { $env:AZURE_NETWORK_ISOLATION } else { "false" }
$AzureDeployVm = if ($env:AZURE_DEPLOY_VM) { $env:AZURE_DEPLOY_VM } else { "false" }
$AzureDeployVpn = if ($env:AZURE_DEPLOY_VPN) { $env:AZURE_DEPLOY_VPN } else { "false" }
$VmUserPassword = if ($env:VM_USER_PASSWORD) { $env:VM_USER_PASSWORD } else { "" }

# Feature flags
$AiVisionEnabled = if ($env:AI_VISION_ENABLED) { $env:AI_VISION_ENABLED } else { "false" }
$AoaiMultiModal = if ($env:AOAI_MULTI_MODAL) { $env:AOAI_MULTI_MODAL } else { "false" }

# Function App settings
$FunctionAppHostPlan = if ($env:FUNCTION_APP_HOST_PLAN) { $env:FUNCTION_APP_HOST_PLAN } else { "FlexConsumption" }
$FunctionAppSku = if ($env:FUNCTION_APP_SKU) { $env:FUNCTION_APP_SKU } else { "FC1" }

# User Principal ID (will be auto-detected if not set)
$UserPrincipalId = if ($env:USER_PRINCIPAL_ID) { $env:USER_PRINCIPAL_ID } else { "" }

# Resource reuse configuration
$AoaiReuse = if ($env:AOAI_REUSE) { $env:AOAI_REUSE } else { "false" }
$AoaiResourceGroupName = if ($env:AOAI_RESOURCE_GROUP_NAME) { $env:AOAI_RESOURCE_GROUP_NAME } else { "" }
$AoaiName = if ($env:AOAI_NAME) { $env:AOAI_NAME } else { "" }

$AppInsightsReuse = if ($env:APP_INSIGHTS_REUSE) { $env:APP_INSIGHTS_REUSE } else { "false" }
$AppInsightsResourceGroupName = if ($env:APP_INSIGHTS_RESOURCE_GROUP_NAME) { $env:APP_INSIGHTS_RESOURCE_GROUP_NAME } else { "" }
$AppInsightsName = if ($env:APP_INSIGHTS_NAME) { $env:APP_INSIGHTS_NAME } else { "" }

$LogAnalyticsWorkspaceReuse = if ($env:LOG_ANALYTICS_WORKSPACE_REUSE) { $env:LOG_ANALYTICS_WORKSPACE_REUSE } else { "false" }
$LogAnalyticsWorkspaceId = if ($env:LOG_ANALYTICS_WORKSPACE_ID) { $env:LOG_ANALYTICS_WORKSPACE_ID } else { "" }

$AppServicePlanReuse = if ($env:APP_SERVICE_PLAN_REUSE) { $env:APP_SERVICE_PLAN_REUSE } else { "false" }
$AppServicePlanResourceGroupName = if ($env:APP_SERVICE_PLAN_RESOURCE_GROUP_NAME) { $env:APP_SERVICE_PLAN_RESOURCE_GROUP_NAME } else { "" }
$AppServicePlanName = if ($env:APP_SERVICE_PLAN_NAME) { $env:APP_SERVICE_PLAN_NAME } else { "" }

$AiSearchReuse = if ($env:AI_SEARCH_REUSE) { $env:AI_SEARCH_REUSE } else { "false" }
$AiSearchResourceGroupName = if ($env:AI_SEARCH_RESOURCE_GROUP_NAME) { $env:AI_SEARCH_RESOURCE_GROUP_NAME } else { "" }
$AiSearchName = if ($env:AI_SEARCH_NAME) { $env:AI_SEARCH_NAME } else { "" }

$AiServicesReuse = if ($env:AI_SERVICES_REUSE) { $env:AI_SERVICES_REUSE } else { "false" }
$AiServicesResourceGroupName = if ($env:AI_SERVICES_RESOURCE_GROUP_NAME) { $env:AI_SERVICES_RESOURCE_GROUP_NAME } else { "" }
$AiServicesName = if ($env:AI_SERVICES_NAME) { $env:AI_SERVICES_NAME } else { "" }

$CosmosDbReuse = if ($env:COSMOS_DB_REUSE) { $env:COSMOS_DB_REUSE } else { "false" }
$CosmosDbResourceGroupName = if ($env:COSMOS_DB_RESOURCE_GROUP_NAME) { $env:COSMOS_DB_RESOURCE_GROUP_NAME } else { "" }
$CosmosDbAccountName = if ($env:COSMOS_DB_ACCOUNT_NAME) { $env:COSMOS_DB_ACCOUNT_NAME } else { "" }
$CosmosDbDatabaseName = if ($env:COSMOS_DB_DATABASE_NAME) { $env:COSMOS_DB_DATABASE_NAME } else { "" }

$KeyVaultReuse = if ($env:KEY_VAULT_REUSE) { $env:KEY_VAULT_REUSE } else { "false" }
$KeyVaultResourceGroupName = if ($env:KEY_VAULT_RESOURCE_GROUP_NAME) { $env:KEY_VAULT_RESOURCE_GROUP_NAME } else { "" }
$KeyVaultName = if ($env:KEY_VAULT_NAME) { $env:KEY_VAULT_NAME } else { "" }

$StorageReuse = if ($env:STORAGE_REUSE) { $env:STORAGE_REUSE } else { "false" }
$StorageResourceGroupName = if ($env:STORAGE_RESOURCE_GROUP_NAME) { $env:STORAGE_RESOURCE_GROUP_NAME } else { "" }
$StorageName = if ($env:STORAGE_NAME) { $env:STORAGE_NAME } else { "" }

$VnetReuse = if ($env:VNET_REUSE) { $env:VNET_REUSE } else { "false" }
$VnetResourceGroupName = if ($env:VNET_RESOURCE_GROUP_NAME) { $env:VNET_RESOURCE_GROUP_NAME } else { "" }
$VnetName = if ($env:VNET_NAME) { $env:VNET_NAME } else { "" }

$OrchestratorFunctionAppReuse = if ($env:ORCHESTRATOR_FUNCTION_APP_REUSE) { $env:ORCHESTRATOR_FUNCTION_APP_REUSE } else { "false" }
$OrchestratorFunctionAppResourceGroupName = if ($env:ORCHESTRATOR_FUNCTION_APP_RESOURCE_GROUP_NAME) { $env:ORCHESTRATOR_FUNCTION_APP_RESOURCE_GROUP_NAME } else { "" }
$OrchestratorFunctionAppName = if ($env:ORCHESTRATOR_FUNCTION_APP_NAME) { $env:ORCHESTRATOR_FUNCTION_APP_NAME } else { "" }

$DataIngestionFunctionAppReuse = if ($env:DATA_INGESTION_FUNCTION_APP_REUSE) { $env:DATA_INGESTION_FUNCTION_APP_REUSE } else { "false" }
$DataIngestionFunctionAppResourceGroupName = if ($env:DATA_INGESTION_FUNCTION_APP_RESOURCE_GROUP_NAME) { $env:DATA_INGESTION_FUNCTION_APP_RESOURCE_GROUP_NAME } else { "" }
$DataIngestionFunctionAppName = if ($env:DATA_INGESTION_FUNCTION_APP_NAME) { $env:DATA_INGESTION_FUNCTION_APP_NAME } else { "" }

$AppServiceReuse = if ($env:APP_SERVICE_REUSE) { $env:APP_SERVICE_REUSE } else { "false" }
$AppServiceName = if ($env:APP_SERVICE_NAME) { $env:APP_SERVICE_NAME } else { "" }
$AppServiceResourceGroupName = if ($env:APP_SERVICE_RESOURCE_GROUP_NAME) { $env:APP_SERVICE_RESOURCE_GROUP_NAME } else { "" }

$OrchestratorFunctionAppStorageReuse = if ($env:ORCHESTRATOR_FUNCTION_APP_STORAGE_REUSE) { $env:ORCHESTRATOR_FUNCTION_APP_STORAGE_REUSE } else { "false" }
$OrchestratorFunctionAppStorageName = if ($env:ORCHESTRATOR_FUNCTION_APP_STORAGE_NAME) { $env:ORCHESTRATOR_FUNCTION_APP_STORAGE_NAME } else { "" }
$OrchestratorFunctionAppStorageResourceGroupName = if ($env:ORCHESTRATOR_FUNCTION_APP_STORAGE_RESOURCE_GROUP_NAME) { $env:ORCHESTRATOR_FUNCTION_APP_STORAGE_RESOURCE_GROUP_NAME } else { "" }

$DataIngestionFunctionAppStorageReuse = if ($env:DATA_INGESTION_FUNCTION_APP_STORAGE_REUSE) { $env:DATA_INGESTION_FUNCTION_APP_STORAGE_REUSE } else { "false" }
$DataIngestionFunctionAppStorageName = if ($env:DATA_INGESTION_FUNCTION_APP_STORAGE_NAME) { $env:DATA_INGESTION_FUNCTION_APP_STORAGE_NAME } else { "" }
$DataIngestionFunctionAppStorageResourceGroupName = if ($env:DATA_INGESTION_FUNCTION_APP_STORAGE_RESOURCE_GROUP_NAME) { $env:DATA_INGESTION_FUNCTION_APP_STORAGE_RESOURCE_GROUP_NAME } else { "" }

##############################################################################
# Functions
##############################################################################

function Test-Prerequisites {
    Write-Info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    try {
        $null = az --version
    }
    catch {
        Write-Error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    }
    
    # Check if logged in to Azure
    try {
        $null = az account show 2>$null
    }
    catch {
        Write-Error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    }
    
    Write-Success "Prerequisites check passed"
}

function Get-UserPrincipalId {
    if ([string]::IsNullOrEmpty($script:UserPrincipalId)) {
        Write-Info "Detecting user principal ID..."
        $script:UserPrincipalId = az ad signed-in-user show --query id -o tsv
        Write-Success "User Principal ID: $($script:UserPrincipalId)"
    }
}

function Set-AzureSubscription {
    if (-not [string]::IsNullOrEmpty($script:AzureSubscriptionId)) {
        Write-Info "Setting subscription to: $($script:AzureSubscriptionId)"
        az account set --subscription $script:AzureSubscriptionId
    }
    else {
        $script:AzureSubscriptionId = az account show --query id -o tsv
        Write-Info "Using current subscription: $($script:AzureSubscriptionId)"
    }
}

function Test-Parameters {
    Write-Info "Validating parameters..."
    
    # Validate required parameters
    if ([string]::IsNullOrEmpty($script:AzureEnvName)) {
        Write-Error "AZURE_ENV_NAME is required"
        exit 1
    }
    
    if ([string]::IsNullOrEmpty($script:AzureLocation)) {
        Write-Error "AZURE_LOCATION is required"
        exit 1
    }
    
    # Set resource group name if not provided
    if ([string]::IsNullOrEmpty($script:AzureResourceGroup)) {
        $script:AzureResourceGroup = "rg-$($script:AzureEnvName)"
        Write-Info "Resource group name not provided, using: $($script:AzureResourceGroup)"
    }
    
    # Validate VM password if VM deployment is enabled
    if ($script:AzureDeployVm -eq "true" -and $script:AzureNetworkIsolation -eq "true") {
        if ([string]::IsNullOrEmpty($script:VmUserPassword)) {
            Write-Error "VM_USER_PASSWORD is required when AZURE_DEPLOY_VM=true and AZURE_NETWORK_ISOLATION=true"
            Write-Error "Password must be 6-72 characters and meet complexity requirements"
            exit 1
        }
    }
    
    Write-Success "Parameter validation passed"
}

function Start-BicepDeployment {
    Write-Info "Starting Bicep deployment..."
    Write-Info "Environment: $($script:AzureEnvName)"
    Write-Info "Location: $($script:AzureLocation)"
    Write-Info "Resource Group: $($script:AzureResourceGroup)"
    Write-Info "Function App Plan: $($script:FunctionAppHostPlan) ($($script:FunctionAppSku))"
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $deploymentName = "main-$($script:AzureEnvName)-$timestamp"
    
    # Build parameters
    $parameters = @{
        environmentName = $script:AzureEnvName
        location = $script:AzureLocation
        aoaiLocation = $script:AoaiLocation
        resourceGroupName = $script:AzureResourceGroup
        principalId = $script:AzurePrincipalId
        userPrincipalId = $script:UserPrincipalId
        networkIsolation = $script:AzureNetworkIsolation
        deployVM = $script:AzureDeployVm
        deployVPN = $script:AzureDeployVpn
        ai_vision_enabled = $script:AiVisionEnabled
        multiModal = $script:AoaiMultiModal
        functionAppHostPlan = $script:FunctionAppHostPlan
        functionAppSKU = $script:FunctionAppSku
    }
    
    # Add VM password if needed
    if ($script:AzureDeployVm -eq "true" -and $script:AzureNetworkIsolation -eq "true") {
        $parameters.vmUserInitialPassword = $script:VmUserPassword
    }
    
    # Build azureReuseConfig object
    $reuseConfig = @{
        aoaiReuse = $script:AoaiReuse
        existingAoaiResourceGroupName = $script:AoaiResourceGroupName
        existingAoaiName = $script:AoaiName
        appInsightsReuse = $script:AppInsightsReuse
        existingAppInsightsResourceGroupName = $script:AppInsightsResourceGroupName
        existingAppInsightsName = $script:AppInsightsName
        logAnalyticsWorkspaceReuse = $script:LogAnalyticsWorkspaceReuse
        existingLogAnalyticsWorkspaceResourceId = $script:LogAnalyticsWorkspaceId
        appServicePlanReuse = $script:AppServicePlanReuse
        existingAppServicePlanResourceGroupName = $script:AppServicePlanResourceGroupName
        existingAppServicePlanName = $script:AppServicePlanName
        aiSearchReuse = $script:AiSearchReuse
        existingAiSearchResourceGroupName = $script:AiSearchResourceGroupName
        existingAiSearchName = $script:AiSearchName
        aiServicesReuse = $script:AiServicesReuse
        existingAiServicesResourceGroupName = $script:AiServicesResourceGroupName
        existingAiServicesName = $script:AiServicesName
        cosmosDbReuse = $script:CosmosDbReuse
        existingCosmosDbResourceGroupName = $script:CosmosDbResourceGroupName
        existingCosmosDbAccountName = $script:CosmosDbAccountName
        existingCosmosDbDatabaseName = $script:CosmosDbDatabaseName
        keyVaultReuse = $script:KeyVaultReuse
        existingKeyVaultResourceGroupName = $script:KeyVaultResourceGroupName
        existingKeyVaultName = $script:KeyVaultName
        storageReuse = $script:StorageReuse
        existingStorageResourceGroupName = $script:StorageResourceGroupName
        existingStorageName = $script:StorageName
        vnetReuse = $script:VnetReuse
        existingVnetResourceGroupName = $script:VnetResourceGroupName
        existingVnetName = $script:VnetName
        orchestratorFunctionAppReuse = $script:OrchestratorFunctionAppReuse
        existingOrchestratorFunctionAppResourceGroupName = $script:OrchestratorFunctionAppResourceGroupName
        existingOrchestratorFunctionAppName = $script:OrchestratorFunctionAppName
        dataIngestionFunctionAppReuse = $script:DataIngestionFunctionAppReuse
        existingDataIngestionFunctionAppResourceGroupName = $script:DataIngestionFunctionAppResourceGroupName
        existingDataIngestionFunctionAppName = $script:DataIngestionFunctionAppName
        appServiceReuse = $script:AppServiceReuse
        existingAppServiceName = $script:AppServiceName
        existingAppServiceNameResourceGroupName = $script:AppServiceResourceGroupName
        orchestratorFunctionAppStorageReuse = $script:OrchestratorFunctionAppStorageReuse
        existingOrchestratorFunctionAppStorageName = $script:OrchestratorFunctionAppStorageName
        existingOrchestratorFunctionAppStorageResourceGroupName = $script:OrchestratorFunctionAppStorageResourceGroupName
        dataIngestionFunctionAppStorageReuse = $script:DataIngestionFunctionAppStorageReuse
        existingDataIngestionFunctionAppStorageName = $script:DataIngestionFunctionAppStorageName
        existingDataIngestionFunctionAppStorageResourceGroupName = $script:DataIngestionFunctionAppStorageResourceGroupName
    }
    
    $reuseConfigJson = $reuseConfig | ConvertTo-Json -Compress -Depth 10
    $parameters.azureReuseConfig = $reuseConfigJson
    
    # Build parameter arguments for az CLI
    $paramArgs = @()
    foreach ($key in $parameters.Keys) {
        $value = $parameters[$key]
        $paramArgs += "$key=$value"
    }
    
    # Execute deployment
    Write-Info "Deploying to subscription: $($script:AzureSubscriptionId)"
    
    try {
        az deployment sub create `
            --name $deploymentName `
            --location $script:AzureLocation `
            --template-file $BicepFile `
            --parameters $paramArgs `
            --output table
        
        Write-Success "Deployment completed successfully!"
        
        # Get deployment outputs
        Write-Info "Retrieving deployment outputs..."
        $outputFile = Join-Path $ScriptDir "deployment-outputs.json"
        az deployment sub show `
            --name $deploymentName `
            --query properties.outputs `
            --output json | Out-File -FilePath $outputFile -Encoding utf8
        
        Write-Success "Deployment outputs saved to: $outputFile"
    }
    catch {
        Write-Error "Deployment failed! $_"
        exit 1
    }
}

function Show-DeploymentSummary {
    Write-Info "==================================================="
    Write-Info "Deployment Summary"
    Write-Info "==================================================="
    Write-Info "Environment:         $($script:AzureEnvName)"
    Write-Info "Subscription:        $($script:AzureSubscriptionId)"
    Write-Info "Resource Group:      $($script:AzureResourceGroup)"
    Write-Info "Location:            $($script:AzureLocation)"
    Write-Info "Network Isolation:   $($script:AzureNetworkIsolation)"
    Write-Info "Deploy VM:           $($script:AzureDeployVm)"
    Write-Info "Deploy VPN:          $($script:AzureDeployVpn)"
    Write-Info "Function App Plan:   $($script:FunctionAppHostPlan)"
    Write-Info "Function App SKU:    $($script:FunctionAppSku)"
    Write-Info "==================================================="
}

##############################################################################
# Main Execution
##############################################################################

function Main {
    Write-Info "==================================================="
    Write-Info "Azure AI Document Processor - Infrastructure Deployment"
    Write-Info "==================================================="
    
    Test-Prerequisites
    Set-AzureSubscription
    Get-UserPrincipalId
    
    # Get principal ID from signed-in user
    $script:AzurePrincipalId = $script:UserPrincipalId
    
    Test-Parameters
    Show-DeploymentSummary
    
    # Ask for confirmation
    $response = Read-Host "Do you want to proceed with the deployment? (yes/no)"
    if ($response -notmatch '^[Yy](es)?$') {
        Write-Warning "Deployment cancelled by user"
        exit 0
    }
    
    Start-BicepDeployment
    
    Write-Success "==================================================="
    Write-Success "Deployment completed successfully!"
    Write-Success "==================================================="
}

# Run main function
Main