#!/bin/bash
#==============================================================================
# check-vm-quota.sh
# Validates which VM SKU families are available on your subscription
# using the Azure Quota API (az quota).
#
# Prerequisites:
#   az extension add --name quota
#   az provider register --namespace Microsoft.Quota
#
# Usage:
#   ./commandUtils/quota/check-vm-quota.sh                          # Uses current subscription + eastus2
#   ./commandUtils/quota/check-vm-quota.sh -l westus2               # Specify location
#   ./commandUtils/quota/check-vm-quota.sh -s <subscription-id>     # Specify subscription
#   ./commandUtils/quota/check-vm-quota.sh -l eastus2 -s <sub-id>   # Both
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

COMPUTE_SCOPE="/subscriptions/$SUBSCRIPTION_ID/providers/Microsoft.Compute/locations/$LOCATION"

echo "============================================================"
echo " VM SKU Family Quota Check"
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
  echo "  ⚠ Microsoft.Quota provider not registered."
  echo "  Run: az provider register --namespace Microsoft.Quota"
fi

# Register Microsoft.Compute — the quota scope provider for VM SKU families
COMPUTE_STATE=$(az provider show --namespace Microsoft.Compute --query "registrationState" -o tsv 2>/dev/null || echo "NotRegistered")
if [[ "$COMPUTE_STATE" != "Registered" ]]; then
  echo "  Registering Microsoft.Compute provider..."
  az provider register --namespace Microsoft.Compute $SUB_FLAG 2>/dev/null
fi
echo ""

#------------------------------------------------------------------------------
# CHECK 1: Regional Totals
#------------------------------------------------------------------------------
echo "━━━ CHECK 1: Regional Totals ━━━"
echo ""

TOTAL_VCPUS_LIMIT=$(az quota show --resource-name "cores" --scope "$COMPUTE_SCOPE" \
  --query "properties.limit.value" -o tsv 2>/dev/null || echo "?")
TOTAL_VCPUS_USED=$(az quota usage show --resource-name "cores" --scope "$COMPUTE_SCOPE" \
  --query "properties.usages.value" -o tsv 2>/dev/null || echo "?")

TOTAL_VMS_LIMIT=$(az quota show --resource-name "virtualMachines" --scope "$COMPUTE_SCOPE" \
  --query "properties.limit.value" -o tsv 2>/dev/null || echo "?")
TOTAL_VMS_USED=$(az quota usage show --resource-name "virtualMachines" --scope "$COMPUTE_SCOPE" \
  --query "properties.usages.value" -o tsv 2>/dev/null || echo "?")

printf "  %-30s %10s %10s %10s\n" "Resource" "Limit" "Used" "Available"
printf "  %-30s %10s %10s %10s\n" "--------" "-----" "----" "---------"
if [[ "$TOTAL_VCPUS_LIMIT" != "?" ]] && [[ "$TOTAL_VCPUS_USED" != "?" ]]; then
  AVAIL=$((TOTAL_VCPUS_LIMIT - TOTAL_VCPUS_USED))
  printf "  %-30s %10s %10s %10s\n" "Total Regional vCPUs" "$TOTAL_VCPUS_LIMIT" "$TOTAL_VCPUS_USED" "$AVAIL"
fi
if [[ "$TOTAL_VMS_LIMIT" != "?" ]] && [[ "$TOTAL_VMS_USED" != "?" ]]; then
  AVAIL=$((TOTAL_VMS_LIMIT - TOTAL_VMS_USED))
  printf "  %-30s %10s %10s %10s\n" "Total VMs" "$TOTAL_VMS_LIMIT" "$TOTAL_VMS_USED" "$AVAIL"
fi
echo ""

#------------------------------------------------------------------------------
# CHECK 2: Families with Active Usage (confirmed working)
#------------------------------------------------------------------------------
echo "━━━ CHECK 2: VM Families with Active Usage (confirmed working) ━━━"
echo ""
az quota usage list --scope "$COMPUTE_SCOPE" \
  --query "[?properties.usages.value > \`0\` && contains(name, 'standard')].{Family:name, vCPUs_InUse:properties.usages.value, Description:properties.name.localizedValue}" \
  -o table 2>/dev/null || echo "  (could not retrieve)"
echo ""

#------------------------------------------------------------------------------
# CHECK 3: Available Families (limit > 0, grouped by type)
#------------------------------------------------------------------------------
echo "━━━ CHECK 3: Available VM Families (Limit > 0) ━━━"
echo ""
echo "  General Purpose (D-series):"
az quota list --scope "$COMPUTE_SCOPE" \
  --query "[?properties.limit.value > \`0\` && (starts_with(name, 'standardD') || starts_with(name, 'StandardD') || starts_with(name, 'standardd'))].{Family:name, Limit:properties.limit.value}" \
  -o table 2>/dev/null || echo "  (none)"
echo ""

echo "  Memory Optimized (E-series):"
az quota list --scope "$COMPUTE_SCOPE" \
  --query "[?properties.limit.value > \`0\` && (starts_with(name, 'standardE') || starts_with(name, 'StandardE'))].{Family:name, Limit:properties.limit.value}" \
  -o table 2>/dev/null || echo "  (none)"
echo ""

echo "  Compute Optimized (F-series):"
az quota list --scope "$COMPUTE_SCOPE" \
  --query "[?properties.limit.value > \`0\` && (starts_with(name, 'standardF') || starts_with(name, 'StandardF'))].{Family:name, Limit:properties.limit.value}" \
  -o table 2>/dev/null || echo "  (none)"
echo ""

echo "  GPU (N-series):"
az quota list --scope "$COMPUTE_SCOPE" \
  --query "[?properties.limit.value > \`0\` && (starts_with(name, 'standardN') || starts_with(name, 'StandardN'))].{Family:name, Limit:properties.limit.value}" \
  -o table 2>/dev/null || echo "  (none)"
echo ""

echo "  Storage Optimized (L-series):"
az quota list --scope "$COMPUTE_SCOPE" \
  --query "[?properties.limit.value > \`0\` && (starts_with(name, 'standardL') || starts_with(name, 'StandardL'))].{Family:name, Limit:properties.limit.value}" \
  -o table 2>/dev/null || echo "  (none)"
echo ""

echo "  High-Performance (H-series):"
az quota list --scope "$COMPUTE_SCOPE" \
  --query "[?properties.limit.value > \`0\` && (starts_with(name, 'standardH') || starts_with(name, 'StandardH'))].{Family:name, Limit:properties.limit.value}" \
  -o table 2>/dev/null || echo "  (none)"
echo ""

#------------------------------------------------------------------------------
# CHECK 4: Blocked Families (limit = 0)
#------------------------------------------------------------------------------
echo "━━━ CHECK 4: Blocked VM Families (Limit = 0) ━━━"
echo ""
az quota list --scope "$COMPUTE_SCOPE" \
  --query "[?properties.limit.value == \`0\` && contains(name, 'standard')].{Family:name, Description:properties.name.localizedValue}" \
  -o table 2>/dev/null || echo "  (could not retrieve)"
echo ""

#------------------------------------------------------------------------------
# Summary
#------------------------------------------------------------------------------
echo "============================================================"
echo " Summary"
echo "============================================================"
echo ""
echo " Total Regional vCPUs: ${TOTAL_VCPUS_USED:-?} / ${TOTAL_VCPUS_LIMIT:-?}"
echo ""
echo " Key commands for further investigation:"
echo ""
echo "   # Check a specific VM family"
echo "   az quota show --resource-name standardDSv3Family \\"
echo "     --scope $COMPUTE_SCOPE"
echo ""
echo "   # Check usage for a specific family"
echo "   az quota usage show --resource-name standardDSv3Family \\"
echo "     --scope $COMPUTE_SCOPE"
echo ""
echo "   # Request quota increase (example: increase DSv3 to 200 vCPUs)"
echo "   az quota update --resource-name standardDSv3Family \\"
echo "     --scope $COMPUTE_SCOPE \\"
echo "     --limit-object value=200 --resource-type dedicated"
echo ""
echo " ⚠ IMPORTANT: Compute quota (limit > 0) does NOT guarantee"
echo "   App Service Plan availability. App Service Plans have a"
echo "   SEPARATE quota system. Use check-asp-quota.sh for ASP checks."
echo ""
