#!/bin/bash
# deploy-testvm.sh - Standalone test VM deployment (VM only, no Bastion)

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Test VM Deployment Script (VM Only) ===${NC}"

# =============================================================================
# CONFIGURATION - Set your parameters here
# =============================================================================

# Option 1: Read from deployment-outputs.json (if it exists)
DEPLOYMENT_OUTPUTS="./infra/deployment-outputs.json"

if [ -f "$DEPLOYMENT_OUTPUTS" ]; then
    echo -e "${GREEN}Reading configuration from deployment-outputs.json...${NC}"
    RESOURCE_GROUP=$(jq -r '.resourcE_GROUP.value' "$DEPLOYMENT_OUTPUTS")
    
    # Try to get vnet name from outputs, fallback to constructed name
    ENVIRONMENT_NAME=$(az group show --name "$RESOURCE_GROUP" --query "tags.\"azd-env-name\"" -o tsv 2>/dev/null || echo "dev")
else
    # Option 2: Set manually
    echo -e "${YELLOW}No deployment-outputs.json found. Using manual configuration.${NC}"
    RESOURCE_GROUP="rg-dev"  # Change this to your resource group name
    ENVIRONMENT_NAME="dev"   # Change this to your environment name
fi

# Common parameters
LOCATION="eastus2"           # Change this to your desired location
VNET_NAME=""                 # Leave empty to create a new VNet automatically
SUBNET_NAME="default"        # Subnet name (will be created if VNet is created)

# VM Configuration
VM_USERNAME="adp-user"
VM_SIZE="Standard_D8s_v5"
VM_IMAGE_SKU="win11-25h2-ent"
VM_IMAGE_PUBLISHER="MicrosoftWindowsDesktop"
VM_IMAGE_OFFER="windows-11"

# VNet Configuration (only used if creating new VNet)
VNET_ADDRESS_PREFIX="10.0.0.0/16"
SUBNET_ADDRESS_PREFIX="10.0.0.0/24"

# Password (will prompt if not set)
VM_PASSWORD="${1:-}"  # Can pass as first argument

# =============================================================================
# Script Logic
# =============================================================================

# Prompt for password if not provided
if [ -z "$VM_PASSWORD" ]; then
    echo -e "${YELLOW}Enter VM admin password (6-72 characters):${NC}"
    read -s VM_PASSWORD
    echo ""
fi

# Validate password
if [ ${#VM_PASSWORD} -lt 6 ] || [ ${#VM_PASSWORD} -gt 72 ]; then
    echo -e "${RED}Error: Password must be between 6-72 characters${NC}"
    exit 1
fi

# Create resource group if it doesn't exist
echo -e "${GREEN}Checking resource group...${NC}"
if ! az group show --name "$RESOURCE_GROUP" &>/dev/null; then
    echo -e "${YELLOW}Resource group '$RESOURCE_GROUP' does not exist. Creating...${NC}"
    az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --tags "azd-env-name=$ENVIRONMENT_NAME"
    echo -e "${GREEN}Resource group created.${NC}"
else
    echo -e "${GREEN}Resource group '$RESOURCE_GROUP' exists.${NC}"
    # Get location from existing resource group
    LOCATION=$(az group show --name "$RESOURCE_GROUP" --query location -o tsv)
fi

# Check if VNet should be auto-detected
if [ -z "$VNET_NAME" ]; then
    echo -e "${GREEN}Auto-detecting VNet...${NC}"
    DETECTED_VNET=$(az network vnet list --resource-group "$RESOURCE_GROUP" --query "[0].name" -o tsv 2>/dev/null)
    
    if [ -n "$DETECTED_VNET" ] && [ "$DETECTED_VNET" != "null" ]; then
        VNET_NAME="$DETECTED_VNET"
        echo -e "${GREEN}Found existing VNet: ${NC}$VNET_NAME"
        
        # Auto-detect subnet
        DETECTED_SUBNET=$(az network vnet subnet list --resource-group "$RESOURCE_GROUP" --vnet-name "$VNET_NAME" --query "[0].name" -o tsv 2>/dev/null)
        if [ -n "$DETECTED_SUBNET" ] && [ "$DETECTED_SUBNET" != "null" ]; then
            SUBNET_NAME="$DETECTED_SUBNET"
            echo -e "${GREEN}Found existing subnet: ${NC}$SUBNET_NAME"
        fi
    else
        echo -e "${YELLOW}No VNet found. A new VNet will be created automatically.${NC}"
    fi
fi

echo ""
echo -e "${GREEN}Deployment Configuration:${NC}"
echo -e "  Resource Group: ${YELLOW}$RESOURCE_GROUP${NC}"
echo -e "  Location: ${YELLOW}$LOCATION${NC}"
if [ -n "$VNET_NAME" ]; then
    echo -e "  VNet Name: ${YELLOW}$VNET_NAME (existing)${NC}"
    echo -e "  Subnet Name: ${YELLOW}$SUBNET_NAME${NC}"
else
    echo -e "  VNet: ${YELLOW}Will be created automatically${NC}"
    echo -e "  VNet Address: ${YELLOW}$VNET_ADDRESS_PREFIX${NC}"
    echo -e "  Subnet Address: ${YELLOW}$SUBNET_ADDRESS_PREFIX${NC}"
fi
echo -e "  Environment: ${YELLOW}$ENVIRONMENT_NAME${NC}"
echo -e "  VM Size: ${YELLOW}$VM_SIZE${NC}"
echo -e "  VM Image: ${YELLOW}$VM_IMAGE_PUBLISHER/$VM_IMAGE_OFFER/$VM_IMAGE_SKU${NC}"
echo ""

# Build parameters
PARAMS="location=\"$LOCATION\" environmentName=\"$ENVIRONMENT_NAME\" vmUserName=\"$VM_USERNAME\" vmUserInitialPassword=\"$VM_PASSWORD\" vmSize=\"$VM_SIZE\" vmImageSku=\"$VM_IMAGE_SKU\" vmImagePublisher=\"$VM_IMAGE_PUBLISHER\" vmImageOffer=\"$VM_IMAGE_OFFER\""

if [ -n "$VNET_NAME" ]; then
    PARAMS="$PARAMS vnetName=\"$VNET_NAME\" subnetName=\"$SUBNET_NAME\""
else
    PARAMS="$PARAMS vnetAddressPrefix=\"$VNET_ADDRESS_PREFIX\" subnetAddressPrefix=\"$SUBNET_ADDRESS_PREFIX\""
fi

# Deploy
echo -e "${GREEN}Deploying Test VM...${NC}"
eval "az deployment group create \
    --resource-group \"$RESOURCE_GROUP\" \
    --template-file ./infra/deploy-testvm.bicep \
    --parameters $PARAMS"

echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo ""
echo -e "${YELLOW}VM deployed without Bastion.${NC}"
echo ""
echo -e "${YELLOW}To connect to the VM:${NC}"
echo "Option 1: Deploy Azure Bastion separately"
echo "Option 2: Add a public IP to the VM"
echo "Option 3: Use VPN/ExpressRoute to connect to the VNet"
echo ""
echo "VM Name: Look for 'testvm-' in resource group: $RESOURCE_GROUP"