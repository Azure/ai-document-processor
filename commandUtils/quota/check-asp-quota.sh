#!/bin/bash
#==============================================================================
# check-asp-quota.sh
# Validates which App Service Plan SKUs are available on your subscription
# using the Azure Quota API (az quota).
#
# Prerequisites:
#   az extension add --name quota
#   az provider register --namespace Microsoft.Quota
#
# Usage:
#   ./commandUtils/quota/check-asp-quota.sh                          # Uses current subscription + eastus2
#   ./commandUtils/quota/check-asp-quota.sh -l westus2               # Specify location
#   ./commandUtils/quota/check-asp-quota.sh -s <subscription-id>     # Specify subscription
#   ./commandUtils/quota/check-asp-quota.sh -l eastus2 -s <sub-id>   # Both
#==============================================================================
set -euo pipefail

# --- Parse arguments ---
LOCATION="eastus2"
SUBSCRIPTION=""

while getopts "l:s:" opt; do
  case $opt in
    l) LOCATION="$OPTARG" ;;
    s) SUBSCRIPTION="$OPTARG" ;;
    *) echo "Usage: $0 [-l location] [-s subscription-id]"; exit 1 ;;
  esac
done

SUB_FLAG=""
SUBSCRIPTION_ID="${SUBSCRIPTION:-$(az account show --query id -o tsv)}"
if [[ -n "$SUBSCRIPTION" ]]; then
  SUB_FLAG="--subscription $SUBSCRIPTION"
fi

WEB_SCOPE="/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Web/locations/$LOCATION"

echo "============================================================"
echo " App Service Plan Quota Check"
echo " Location: $LOCATION"
echo " Subscription: $SUBSCRIPTION_ID"
echo "============================================================"
echo ""

#------------------------------------------------------------------------------
# PREREQUISITE: Ensure 'quota' extension and Microsoft.Quota provider
#------------------------------------------------------------------------------
echo "Checking prerequisites..."
az extension add --name quota --only-show-errors 2>/dev/null || true

# Register Microsoft.Quota — required by the 'az quota' extension
QUOTA_STATE=$(az provider show --namespace Microsoft.Quota --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")
if [[ "$QUOTA_STATE" != "Registered" ]]; then
  echo "  Registering Microsoft.Quota provider (may take up to 2 min)..."
  az provider register --namespace Microsoft.Quota $SUB_FLAG 2>/dev/null
  for i in {1..24}; do
    QUOTA_STATE=$(az provider show --namespace Microsoft.Quota --query "registrationState" -o tsv 2>/dev/null)
    [[ "$QUOTA_STATE" == "Registered" ]] && break
    sleep 5
  done
fi

if [[ "$QUOTA_STATE" != "Registered" ]]; then
  echo "  ⚠ Microsoft.Quota provider not registered. CHECKs 1-2 may fail."
  echo "  Run: az provider register --namespace Microsoft.Quota"
fi

# Register Microsoft.Web — the quota scope provider for App Service Plans
WEB_STATE=$(az provider show --namespace Microsoft.Web --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")
if [[ "$WEB_STATE" != "Registered" ]]; then
  echo "  Registering Microsoft.Web provider..."
  az provider register --namespace Microsoft.Web $SUB_FLAG 2>/dev/null
fi
echo ""

#------------------------------------------------------------------------------
# CHECK 1: Regional Aggregate Limit (MOST IMPORTANT)
#
# The "Total Regional VMs" quota in Microsoft.Web is the master gate.
# If this is 0, ALL App Service Plan tiers are blocked regardless of
# individual SKU limits.
#------------------------------------------------------------------------------
echo "━━━ CHECK 1: Regional Aggregate Limit (Master Gate) ━━━"
echo ""

TOTAL_REGIONAL=$(az quota show --resource-name "*" --scope "$WEB_SCOPE" \
  --query "properties.limit.value" -o tsv 2>/dev/null || echo "ERROR")

if [[ "$TOTAL_REGIONAL" == "0" ]]; then
  echo "  ❌ Total Regional VMs limit: 0"
  echo ""
  echo "  ALL App Service Plan tiers are BLOCKED in $LOCATION."
  echo "  Individual SKU limits (even if >0) are overridden by this aggregate."
  echo ""
  echo "  To unblock, request a quota increase:"
  echo "    https://aka.ms/antquotahelp"
  echo ""
  echo "  Only FlexConsumption (FC1) bypasses this — it uses Container Apps"
  echo "  infrastructure, not App Service VMs."
  echo ""
elif [[ "$TOTAL_REGIONAL" == "ERROR" ]]; then
  echo "  ⚠ Could not read Total Regional VMs quota."
  echo "  Ensure Microsoft.Quota provider is registered."
  echo ""
else
  echo "  ✅ Total Regional VMs limit: $TOTAL_REGIONAL"
  echo "  App Service Plans can potentially be deployed."
  echo ""
fi

#------------------------------------------------------------------------------
# CHECK 2: Per-SKU Quota Limits (az quota list for Microsoft.Web)
#
# Shows individual SKU limits. A limit > 0 means the SKU is potentially
# available, but it's still gated by the regional aggregate (CHECK 1).
# A per-SKU limit of 0 is definitively blocked.
#------------------------------------------------------------------------------
echo "━━━ CHECK 2: Per-SKU Quota Limits ━━━"
echo ""
echo "  SKUs with Limit > 0 (potentially available if CHECK 1 passes):"
az quota list --scope "$WEB_SCOPE" \
  --query "[?properties.limit.value > \`0\`].{SKU:name, Limit:properties.limit.value, Description:properties.name.localizedValue}" \
  -o table 2>/dev/null || echo "  (could not retrieve)"
echo ""
echo "  SKUs with Limit = 0 (definitively blocked):"
az quota list --scope "$WEB_SCOPE" \
  --query "[?properties.limit.value == \`0\` && name != '*'].{SKU:name, Limit:properties.limit.value, Description:properties.name.localizedValue}" \
  -o table 2>/dev/null || echo "  (could not retrieve)"
echo ""

#------------------------------------------------------------------------------
# CHECK 3: Current Usage
#
# Shows which SKUs already have instances running.
# If a SKU has usage > 0, it is CONFIRMED deployable.
#------------------------------------------------------------------------------
echo "━━━ CHECK 3: Current Usage ━━━"
echo ""
echo "  SKUs with active instances (confirmed working):"
USAGE_LIST=$(az quota usage list --scope "$WEB_SCOPE" \
  --query "[?properties.usages.value > \`0\`].{SKU:name, InUse:properties.usages.value, Description:properties.name.localizedValue}" \
  -o table 2>/dev/null || echo "")

if [[ -n "$USAGE_LIST" ]] && [[ "$USAGE_LIST" != *"(could not"* ]]; then
  echo "$USAGE_LIST"
else
  echo "  (no active App Service Plan instances found)"
fi
echo ""

#------------------------------------------------------------------------------
# CHECK 4: Existing App Service Plans
#
# Lists any ASPs already deployed in the subscription.
#------------------------------------------------------------------------------
echo "━━━ CHECK 4: Existing App Service Plans ━━━"
echo ""
az appservice plan list $SUB_FLAG \
  --query "[].{Name:name, SKU:sku.name, Tier:sku.tier, Location:location, RG:resourceGroup}" \
  -o table 2>/dev/null || echo "  No App Service Plans found."
echo ""

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
echo "============================================================"
echo " Summary"
echo "============================================================"
echo ""
echo " Total Regional VMs limit: ${TOTAL_REGIONAL:-unknown}"
echo ""
if [[ "$TOTAL_REGIONAL" == "0" ]]; then
  echo " ❌ This subscription CANNOT deploy any App Service Plan in $LOCATION."
  echo ""
  echo " Options:"
  echo "   1. Request quota increase: https://aka.ms/antquotahelp"
  echo "   2. Use FlexConsumption (FC1) — uses Container Apps, bypasses VM quota"
  echo "   3. Use a different subscription without these restrictions"
  echo ""
elif [[ "$TOTAL_REGIONAL" != "ERROR" ]]; then
  echo " ✅ App Service Plans are available. Use CHECK 2 to see per-SKU limits."
  echo ""
fi
echo " Key commands for further investigation:"
echo ""
echo "   # Check a specific SKU limit"
echo "   az quota show --resource-name S2 \\"
echo "     --scope $WEB_SCOPE"
echo ""
echo "   # Check usage for a specific SKU"
echo "   az quota usage show --resource-name P1v3 \\"
echo "     --scope $WEB_SCOPE"
echo ""
echo "   # Request quota increase (example: increase S2 to 10 instances)"
echo "   az quota update --resource-name S2 \\"
echo "     --scope $WEB_SCOPE \\"
echo "     --limit-object value=10 --resource-type dedicated"
echo ""
