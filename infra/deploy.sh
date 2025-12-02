#!/bin/bash

##############################################################################
# Azure Bicep Deployment Script
# This script deploys the main.bicep infrastructure template
##############################################################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BICEP_FILE="${SCRIPT_DIR}/main.bicep"
PARAMS_FILE="${SCRIPT_DIR}/main.parameters.json"

##############################################################################
# Configuration - Set these variables or export them as environment variables
##############################################################################

# Required parameters
AZURE_SUBSCRIPTION_ID="${AZURE_SUBSCRIPTION_ID:-}"
AZURE_ENV_NAME="${AZURE_ENV_NAME:-dev}"
AZURE_LOCATION="${AZURE_LOCATION:-eastus2}"
AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-}"

# Azure OpenAI location (must be one of the allowed locations)
AOAI_LOCATION="${AOAI_LOCATION:-East US}"

# Network and VM settings
AZURE_NETWORK_ISOLATION="${AZURE_NETWORK_ISOLATION:-false}"
AZURE_DEPLOY_VM="${AZURE_DEPLOY_VM:-false}"
AZURE_DEPLOY_VPN="${AZURE_DEPLOY_VPN:-false}"
VM_USER_PASSWORD="${VM_USER_PASSWORD:-}"

# Feature flags
AI_VISION_ENABLED="${AI_VISION_ENABLED:-false}"
AOAI_MULTI_MODAL="${AOAI_MULTI_MODAL:-false}"

# Function App settings
FUNCTION_APP_HOST_PLAN="${FUNCTION_APP_HOST_PLAN:-FlexConsumption}"  # FlexConsumption or Dedicated
FUNCTION_APP_SKU="${FUNCTION_APP_SKU:-FC1}"  # FC1 for FlexConsumption, or S2, B1, P1v2, etc. for Dedicated

# User Principal ID (will be auto-detected if not set)
USER_PRINCIPAL_ID="${USER_PRINCIPAL_ID:-}"

# Resource reuse configuration (set to "true" to reuse existing resources)
AOAI_REUSE="${AOAI_REUSE:-false}"
AOAI_RESOURCE_GROUP_NAME="${AOAI_RESOURCE_GROUP_NAME:-}"
AOAI_NAME="${AOAI_NAME:-}"

APP_INSIGHTS_REUSE="${APP_INSIGHTS_REUSE:-false}"
APP_INSIGHTS_RESOURCE_GROUP_NAME="${APP_INSIGHTS_RESOURCE_GROUP_NAME:-}"
APP_INSIGHTS_NAME="${APP_INSIGHTS_NAME:-}"

LOG_ANALYTICS_WORKSPACE_REUSE="${LOG_ANALYTICS_WORKSPACE_REUSE:-false}"
LOG_ANALYTICS_WORKSPACE_ID="${LOG_ANALYTICS_WORKSPACE_ID:-}"

APP_SERVICE_PLAN_REUSE="${APP_SERVICE_PLAN_REUSE:-false}"
APP_SERVICE_PLAN_RESOURCE_GROUP_NAME="${APP_SERVICE_PLAN_RESOURCE_GROUP_NAME:-}"
APP_SERVICE_PLAN_NAME="${APP_SERVICE_PLAN_NAME:-}"

AI_SEARCH_REUSE="${AI_SEARCH_REUSE:-false}"
AI_SEARCH_RESOURCE_GROUP_NAME="${AI_SEARCH_RESOURCE_GROUP_NAME:-}"
AI_SEARCH_NAME="${AI_SEARCH_NAME:-}"

AI_SERVICES_REUSE="${AI_SERVICES_REUSE:-false}"
AI_SERVICES_RESOURCE_GROUP_NAME="${AI_SERVICES_RESOURCE_GROUP_NAME:-}"
AI_SERVICES_NAME="${AI_SERVICES_NAME:-}"

COSMOS_DB_REUSE="${COSMOS_DB_REUSE:-false}"
COSMOS_DB_RESOURCE_GROUP_NAME="${COSMOS_DB_RESOURCE_GROUP_NAME:-}"
COSMOS_DB_ACCOUNT_NAME="${COSMOS_DB_ACCOUNT_NAME:-}"
COSMOS_DB_DATABASE_NAME="${COSMOS_DB_DATABASE_NAME:-}"

KEY_VAULT_REUSE="${KEY_VAULT_REUSE:-false}"
KEY_VAULT_RESOURCE_GROUP_NAME="${KEY_VAULT_RESOURCE_GROUP_NAME:-}"
KEY_VAULT_NAME="${KEY_VAULT_NAME:-}"

STORAGE_REUSE="${STORAGE_REUSE:-false}"
STORAGE_RESOURCE_GROUP_NAME="${STORAGE_RESOURCE_GROUP_NAME:-}"
STORAGE_NAME="${STORAGE_NAME:-}"

VNET_REUSE="${VNET_REUSE:-false}"
VNET_RESOURCE_GROUP_NAME="${VNET_RESOURCE_GROUP_NAME:-}"
VNET_NAME="${VNET_NAME:-}"

ORCHESTRATOR_FUNCTION_APP_REUSE="${ORCHESTRATOR_FUNCTION_APP_REUSE:-false}"
ORCHESTRATOR_FUNCTION_APP_RESOURCE_GROUP_NAME="${ORCHESTRATOR_FUNCTION_APP_RESOURCE_GROUP_NAME:-}"
ORCHESTRATOR_FUNCTION_APP_NAME="${ORCHESTRATOR_FUNCTION_APP_NAME:-}"

DATA_INGESTION_FUNCTION_APP_REUSE="${DATA_INGESTION_FUNCTION_APP_REUSE:-false}"
DATA_INGESTION_FUNCTION_APP_RESOURCE_GROUP_NAME="${DATA_INGESTION_FUNCTION_APP_RESOURCE_GROUP_NAME:-}"
DATA_INGESTION_FUNCTION_APP_NAME="${DATA_INGESTION_FUNCTION_APP_NAME:-}"

APP_SERVICE_REUSE="${APP_SERVICE_REUSE:-false}"
APP_SERVICE_NAME="${APP_SERVICE_NAME:-}"
APP_SERVICE_RESOURCE_GROUP_NAME="${APP_SERVICE_RESOURCE_GROUP_NAME:-}"

ORCHESTRATOR_FUNCTION_APP_STORAGE_REUSE="${ORCHESTRATOR_FUNCTION_APP_STORAGE_REUSE:-false}"
ORCHESTRATOR_FUNCTION_APP_STORAGE_NAME="${ORCHESTRATOR_FUNCTION_APP_STORAGE_NAME:-}"
ORCHESTRATOR_FUNCTION_APP_STORAGE_RESOURCE_GROUP_NAME="${ORCHESTRATOR_FUNCTION_APP_STORAGE_RESOURCE_GROUP_NAME:-}"

DATA_INGESTION_FUNCTION_APP_STORAGE_REUSE="${DATA_INGESTION_FUNCTION_APP_STORAGE_REUSE:-false}"
DATA_INGESTION_FUNCTION_APP_STORAGE_NAME="${DATA_INGESTION_FUNCTION_APP_STORAGE_NAME:-}"
DATA_INGESTION_FUNCTION_APP_STORAGE_RESOURCE_GROUP_NAME="${DATA_INGESTION_FUNCTION_APP_STORAGE_RESOURCE_GROUP_NAME:-}"

##############################################################################
# Functions
##############################################################################

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Azure CLI is installed
    if ! command -v az &> /dev/null; then
        log_error "Azure CLI is not installed. Please install it from https://docs.microsoft.com/en-us/cli/azure/install-azure-cli"
        exit 1
    fi
    
    # Check if logged in to Azure
    if ! az account show &> /dev/null; then
        log_error "Not logged in to Azure. Please run 'az login' first."
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

get_user_principal_id() {
    if [ -z "$USER_PRINCIPAL_ID" ]; then
        log_info "Detecting user principal ID..."
        USER_PRINCIPAL_ID=$(az ad signed-in-user show --query id -o tsv)
        log_success "User Principal ID: $USER_PRINCIPAL_ID"
    fi
}

set_subscription() {
    if [ -n "$AZURE_SUBSCRIPTION_ID" ]; then
        log_info "Setting subscription to: $AZURE_SUBSCRIPTION_ID"
        az account set --subscription "$AZURE_SUBSCRIPTION_ID"
    else
        AZURE_SUBSCRIPTION_ID=$(az account show --query id -o tsv)
        log_info "Using current subscription: $AZURE_SUBSCRIPTION_ID"
    fi
}

validate_parameters() {
    log_info "Validating parameters..."
    
    # Validate required parameters
    if [ -z "$AZURE_ENV_NAME" ]; then
        log_error "AZURE_ENV_NAME is required"
        exit 1
    fi
    
    if [ -z "$AZURE_LOCATION" ]; then
        log_error "AZURE_LOCATION is required"
        exit 1
    fi
    
    # Set resource group name if not provided
    if [ -z "$AZURE_RESOURCE_GROUP" ]; then
        AZURE_RESOURCE_GROUP="rg-${AZURE_ENV_NAME}"
        log_info "Resource group name not provided, using: $AZURE_RESOURCE_GROUP"
    fi
    
    # Validate VM password if VM deployment is enabled
    if [ "$AZURE_DEPLOY_VM" = "true" ] && [ "$AZURE_NETWORK_ISOLATION" = "true" ]; then
        if [ -z "$VM_USER_PASSWORD" ]; then
            log_error "VM_USER_PASSWORD is required when AZURE_DEPLOY_VM=true and AZURE_NETWORK_ISOLATION=true"
            log_error "Password must be 6-72 characters and meet complexity requirements"
            exit 1
        fi
    fi
    
    log_success "Parameter validation passed"
}

deploy_bicep() {
    log_info "Starting Bicep deployment..."
    log_info "Environment: $AZURE_ENV_NAME"
    log_info "Location: $AZURE_LOCATION"
    log_info "Resource Group: $AZURE_RESOURCE_GROUP"
    log_info "Function App Plan: $FUNCTION_APP_HOST_PLAN ($FUNCTION_APP_SKU)"
    
    DEPLOYMENT_NAME="main-${AZURE_ENV_NAME}-$(date +%Y%m%d-%H%M%S)"
    
    # Build parameters array
    PARAMS=(
        "environmentName=$AZURE_ENV_NAME"
        "location=$AZURE_LOCATION"
        "aoaiLocation=$AOAI_LOCATION"
        "resourceGroupName=$AZURE_RESOURCE_GROUP"
        "principalId=$AZURE_PRINCIPAL_ID"
        "userPrincipalId=$USER_PRINCIPAL_ID"
        "networkIsolation=$AZURE_NETWORK_ISOLATION"
        "deployVM=$AZURE_DEPLOY_VM"
        "deployVPN=$AZURE_DEPLOY_VPN"
        "ai_vision_enabled=$AI_VISION_ENABLED"
        "multiModal=$AOAI_MULTI_MODAL"
        "functionAppHostPlan=$FUNCTION_APP_HOST_PLAN"
        "functionAppSKU=$FUNCTION_APP_SKU"
    )
    
    # Add VM password if needed
    if [ "$AZURE_DEPLOY_VM" = "true" ] && [ "$AZURE_NETWORK_ISOLATION" = "true" ]; then
        PARAMS+=("vmUserInitialPassword=$VM_USER_PASSWORD")
    fi
    
    # Build azureReuseConfig object
    REUSE_CONFIG="{"
    REUSE_CONFIG+="\"aoaiReuse\":\"$AOAI_REUSE\","
    REUSE_CONFIG+="\"existingAoaiResourceGroupName\":\"$AOAI_RESOURCE_GROUP_NAME\","
    REUSE_CONFIG+="\"existingAoaiName\":\"$AOAI_NAME\","
    REUSE_CONFIG+="\"appInsightsReuse\":\"$APP_INSIGHTS_REUSE\","
    REUSE_CONFIG+="\"existingAppInsightsResourceGroupName\":\"$APP_INSIGHTS_RESOURCE_GROUP_NAME\","
    REUSE_CONFIG+="\"existingAppInsightsName\":\"$APP_INSIGHTS_NAME\","
    REUSE_CONFIG+="\"logAnalyticsWorkspaceReuse\":\"$LOG_ANALYTICS_WORKSPACE_REUSE\","
    REUSE_CONFIG+="\"existingLogAnalyticsWorkspaceResourceId\":\"$LOG_ANALYTICS_WORKSPACE_ID\","
    REUSE_CONFIG+="\"appServicePlanReuse\":\"$APP_SERVICE_PLAN_REUSE\","
    REUSE_CONFIG+="\"existingAppServicePlanResourceGroupName\":\"$APP_SERVICE_PLAN_RESOURCE_GROUP_NAME\","
    REUSE_CONFIG+="\"existingAppServicePlanName\":\"$APP_SERVICE_PLAN_NAME\","
    REUSE_CONFIG+="\"aiSearchReuse\":\"$AI_SEARCH_REUSE\","
    REUSE_CONFIG+="\"existingAiSearchResourceGroupName\":\"$AI_SEARCH_RESOURCE_GROUP_NAME\","
    REUSE_CONFIG+="\"existingAiSearchName\":\"$AI_SEARCH_NAME\","
    REUSE_CONFIG+="\"aiServicesReuse\":\"$AI_SERVICES_REUSE\","
    REUSE_CONFIG+="\"existingAiServicesResourceGroupName\":\"$AI_SERVICES_RESOURCE_GROUP_NAME\","
    REUSE_CONFIG+="\"existingAiServicesName\":\"$AI_SERVICES_NAME\","
    REUSE_CONFIG+="\"cosmosDbReuse\":\"$COSMOS_DB_REUSE\","
    REUSE_CONFIG+="\"existingCosmosDbResourceGroupName\":\"$COSMOS_DB_RESOURCE_GROUP_NAME\","
    REUSE_CONFIG+="\"existingCosmosDbAccountName\":\"$COSMOS_DB_ACCOUNT_NAME\","
    REUSE_CONFIG+="\"existingCosmosDbDatabaseName\":\"$COSMOS_DB_DATABASE_NAME\","
    REUSE_CONFIG+="\"keyVaultReuse\":\"$KEY_VAULT_REUSE\","
    REUSE_CONFIG+="\"existingKeyVaultResourceGroupName\":\"$KEY_VAULT_RESOURCE_GROUP_NAME\","
    REUSE_CONFIG+="\"existingKeyVaultName\":\"$KEY_VAULT_NAME\","
    REUSE_CONFIG+="\"storageReuse\":\"$STORAGE_REUSE\","
    REUSE_CONFIG+="\"existingStorageResourceGroupName\":\"$STORAGE_RESOURCE_GROUP_NAME\","
    REUSE_CONFIG+="\"existingStorageName\":\"$STORAGE_NAME\","
    REUSE_CONFIG+="\"vnetReuse\":\"$VNET_REUSE\","
    REUSE_CONFIG+="\"existingVnetResourceGroupName\":\"$VNET_RESOURCE_GROUP_NAME\","
    REUSE_CONFIG+="\"existingVnetName\":\"$VNET_NAME\","
    REUSE_CONFIG+="\"orchestratorFunctionAppReuse\":\"$ORCHESTRATOR_FUNCTION_APP_REUSE\","
    REUSE_CONFIG+="\"existingOrchestratorFunctionAppResourceGroupName\":\"$ORCHESTRATOR_FUNCTION_APP_RESOURCE_GROUP_NAME\","
    REUSE_CONFIG+="\"existingOrchestratorFunctionAppName\":\"$ORCHESTRATOR_FUNCTION_APP_NAME\","
    REUSE_CONFIG+="\"dataIngestionFunctionAppReuse\":\"$DATA_INGESTION_FUNCTION_APP_REUSE\","
    REUSE_CONFIG+="\"existingDataIngestionFunctionAppResourceGroupName\":\"$DATA_INGESTION_FUNCTION_APP_RESOURCE_GROUP_NAME\","
    REUSE_CONFIG+="\"existingDataIngestionFunctionAppName\":\"$DATA_INGESTION_FUNCTION_APP_NAME\","
    REUSE_CONFIG+="\"appServiceReuse\":\"$APP_SERVICE_REUSE\","
    REUSE_CONFIG+="\"existingAppServiceName\":\"$APP_SERVICE_NAME\","
    REUSE_CONFIG+="\"existingAppServiceNameResourceGroupName\":\"$APP_SERVICE_RESOURCE_GROUP_NAME\","
    REUSE_CONFIG+="\"orchestratorFunctionAppStorageReuse\":\"$ORCHESTRATOR_FUNCTION_APP_STORAGE_REUSE\","
    REUSE_CONFIG+="\"existingOrchestratorFunctionAppStorageName\":\"$ORCHESTRATOR_FUNCTION_APP_STORAGE_NAME\","
    REUSE_CONFIG+="\"existingOrchestratorFunctionAppStorageResourceGroupName\":\"$ORCHESTRATOR_FUNCTION_APP_STORAGE_RESOURCE_GROUP_NAME\","
    REUSE_CONFIG+="\"dataIngestionFunctionAppStorageReuse\":\"$DATA_INGESTION_FUNCTION_APP_STORAGE_REUSE\","
    REUSE_CONFIG+="\"existingDataIngestionFunctionAppStorageName\":\"$DATA_INGESTION_FUNCTION_APP_STORAGE_NAME\","
    REUSE_CONFIG+="\"existingDataIngestionFunctionAppStorageResourceGroupName\":\"$DATA_INGESTION_FUNCTION_APP_STORAGE_RESOURCE_GROUP_NAME\""
    REUSE_CONFIG+="}"
    
    PARAMS+=("azureReuseConfig=$REUSE_CONFIG")
    
    # Execute deployment
    log_info "Deploying to subscription: $AZURE_SUBSCRIPTION_ID"
    
    az deployment sub create \
        --name "$DEPLOYMENT_NAME" \
        --location "$AZURE_LOCATION" \
        --template-file "$BICEP_FILE" \
        --parameters "${PARAMS[@]}" \
        --output table
    
    if [ $? -eq 0 ]; then
        log_success "Deployment completed successfully!"
        
        # Get deployment outputs
        log_info "Retrieving deployment outputs..."
        az deployment sub show \
            --name "$DEPLOYMENT_NAME" \
            --query properties.outputs \
            --output json > deployment-outputs.json
        
        log_success "Deployment outputs saved to: deployment-outputs.json"
    else
        log_error "Deployment failed!"
        exit 1
    fi
}

print_summary() {
    log_info "==================================================="
    log_info "Deployment Summary"
    log_info "==================================================="
    log_info "Environment:         $AZURE_ENV_NAME"
    log_info "Subscription:        $AZURE_SUBSCRIPTION_ID"
    log_info "Resource Group:      $AZURE_RESOURCE_GROUP"
    log_info "Location:            $AZURE_LOCATION"
    log_info "Network Isolation:   $AZURE_NETWORK_ISOLATION"
    log_info "Deploy VM:           $AZURE_DEPLOY_VM"
    log_info "Deploy VPN:          $AZURE_DEPLOY_VPN"
    log_info "Function App Plan:   $FUNCTION_APP_HOST_PLAN"
    log_info "Function App SKU:    $FUNCTION_APP_SKU"
    log_info "==================================================="
}

##############################################################################
# Main execution
##############################################################################

main() {
    log_info "==================================================="
    log_info "Azure AI Document Processor - Infrastructure Deployment"
    log_info "==================================================="
    
    check_prerequisites
    set_subscription
    get_user_principal_id
    
    # Get principal ID from signed-in user
    AZURE_PRINCIPAL_ID=$USER_PRINCIPAL_ID
    
    validate_parameters
    print_summary
    
    # Ask for confirmation
    read -p "Do you want to proceed with the deployment? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy]es$ ]]; then
        log_warning "Deployment cancelled by user"
        exit 0
    fi
    
    deploy_bicep
    
    log_success "==================================================="
    log_success "Deployment completed successfully!"
    log_success "==================================================="
}

# Run main function
main
