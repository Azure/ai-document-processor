#!/usr/bin/env bash
# =============================================================================
# find-vm-sku.sh
# =============================================================================
# Finds an available VM SKU in a given Azure region based on filters.
# Replicates the behavior of the Terraform module:
#   Azure/avm-utl-sku-finder/azapi
#
# Prerequisites:
#   - Azure CLI (az) authenticated and targeting the correct subscription
#   - jq >= 1.6
#
# Usage:
#   ./scripts/find-vm-sku.sh --location <region> [options]
#
# Options:
#   --location <region>             Azure region (required). E.g. eastus2
#   --min-vcpus <n>                 Minimum vCPU count (default: 1)
#   --max-vcpus <n>                 Maximum vCPU count (default: 999)
#   --arch <x64|Arm64>              CPU architecture (default: x64)
#   --encryption-at-host <true|false>
#                                   Filter by encryption-at-host support
#   --accelerated-networking <true|false>
#                                   Filter by accelerated networking support
#   --name-pattern <regex>          Regex applied to SKU name.
#                                   E.g. "Standard_D[0-9]+s_v[34]$"
#   --exclude-zone-restrictions     Only return SKUs with NO zone restrictions.
#                                   By default, SKUs blocked only in zone 1 are
#                                   still included (safe when no zone is pinned).
#   --all                           Print all matching SKUs with details instead
#                                   of just the first match.
#
# Exit codes:
#   0 — at least one match found (first match printed to stdout)
#   1 — no match found for the given filters
#
# Examples:
#   # Equivalent to the Terraform "vm_sku" module (2 vCPUs, secure):
#   ./scripts/find-vm-sku.sh \
#     --location eastus2 \
#     --min-vcpus 2 --max-vcpus 2 \
#     --encryption-at-host true \
#     --accelerated-networking true
#
#   # Equivalent to the Terraform "linux_vm_sku" module (relaxed, 1-2 vCPUs):
#   ./scripts/find-vm-sku.sh \
#     --location eastus2 \
#     --min-vcpus 1 --max-vcpus 2
#
#   # DSv3/v4 family only, 4-8 vCPUs, show all matches:
#   ./scripts/find-vm-sku.sh \
#     --location eastus2 \
#     --min-vcpus 4 --max-vcpus 8 \
#     --name-pattern "Standard_D[0-9]+s_v[34]$" \
#     --all
#
#   # Capture result and set it as the azd VM size:
#   VM_SKU=$(./scripts/find-vm-sku.sh \
#     --location eastus2 \
#     --min-vcpus 4 --max-vcpus 8 \
#     --name-pattern "Standard_D[0-9]+s_v[34]$")
#   azd env set AZURE_VM_SIZE "$VM_SKU"
# =============================================================================

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────
LOCATION=""
MIN_VCPUS=1
MAX_VCPUS=999
ARCH="x64"
ENCRYPTION_AT_HOST=""      # true | false | "" (any)
ACCELERATED_NETWORKING=""  # true | false | "" (any)
NAME_PATTERN=""            # regex applied to SKU name
EXCLUDE_ZONE_RESTRICTIONS=false
ALL=false

# ── Arg parsing ───────────────────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --location)               LOCATION="$2";               shift 2 ;;
    --min-vcpus)              MIN_VCPUS="$2";              shift 2 ;;
    --max-vcpus)              MAX_VCPUS="$2";              shift 2 ;;
    --arch)                   ARCH="$2";                   shift 2 ;;
    --encryption-at-host)     ENCRYPTION_AT_HOST="$2";     shift 2 ;;
    --accelerated-networking) ACCELERATED_NETWORKING="$2"; shift 2 ;;
    --name-pattern)           NAME_PATTERN="$2";           shift 2 ;;
    --exclude-zone-restrictions) EXCLUDE_ZONE_RESTRICTIONS=true; shift ;;
    --all)                    ALL=true;                    shift ;;
    -h|--help)
      head -60 "$0" | tail -55 | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$LOCATION" ]]; then
  echo "Error: --location is required" >&2
  exit 1
fi

echo "🔍 Querying VM SKUs in $LOCATION..." >&2

# ── Build jq filter ───────────────────────────────────────────────────────────
JQ_FILTER='
def cap(name): (.capabilities // [] | map(select(.name == name)) | first // {value: ""} | .value);
def capnum(name): (cap(name) | tonumber? // 0);
def capbool(name): (cap(name) | ascii_downcase == "true");

.[]
| select(.resourceType == "virtualMachines")

| select(
    (.restrictions // [])
    | map(select(.type == "Location"))
    | length == 0
  )
'

if [[ "$EXCLUDE_ZONE_RESTRICTIONS" == "true" ]]; then
  JQ_FILTER+='
| select((.restrictions // []) | length == 0)
'
fi

JQ_FILTER+="
| select(capnum(\"vCPUs\") >= ${MIN_VCPUS})
| select(capnum(\"vCPUs\") <= ${MAX_VCPUS})
"

if [[ -n "$ARCH" ]]; then
  JQ_FILTER+="
| select(cap(\"CpuArchitectureType\") == \"${ARCH}\")
"
fi

if [[ "$ENCRYPTION_AT_HOST" == "true" ]]; then
  JQ_FILTER+='
| select(capbool("EncryptionAtHostSupported"))
'
elif [[ "$ENCRYPTION_AT_HOST" == "false" ]]; then
  JQ_FILTER+='
| select(capbool("EncryptionAtHostSupported") | not)
'
fi

if [[ "$ACCELERATED_NETWORKING" == "true" ]]; then
  JQ_FILTER+='
| select(capbool("AcceleratedNetworkingEnabled"))
'
elif [[ "$ACCELERATED_NETWORKING" == "false" ]]; then
  JQ_FILTER+='
| select(capbool("AcceleratedNetworkingEnabled") | not)
'
fi

if [[ -n "$NAME_PATTERN" ]]; then
  JQ_FILTER+="
| select(.name | test(\"${NAME_PATTERN}\"))
"
fi

# ── Execute ───────────────────────────────────────────────────────────────────
RAW=$(az vm list-skus \
  --location "$LOCATION" \
  --resource-type virtualMachines \
  --output json 2>/dev/null)

if [[ "$ALL" == "true" ]]; then
  MATCHES=$(echo "$RAW" | jq -r "
    [ ${JQ_FILTER}
      | {
          name: .name,
          vcpus: capnum(\"vCPUs\"),
          ram_gb: ((capnum(\"MemoryGB\") * 10 | round) / 10),
          encryption_at_host: capbool(\"EncryptionAtHostSupported\"),
          accelerated_networking: capbool(\"AcceleratedNetworkingEnabled\"),
          zone_restrictions: ([ (.restrictions // [])[] | select(.type == \"Zone\") | .restrictionInfo.zones[] ] | unique)
        }
    ]" 2>/dev/null)

  COUNT=$(echo "$MATCHES" | jq 'length')
  if [[ "$COUNT" -eq 0 ]]; then
    echo "❌ No SKUs found matching the given filters in $LOCATION" >&2
    exit 1
  fi

  echo "✅ Found $COUNT matching SKU(s):" >&2
  echo ""
  echo "$MATCHES" | jq -r '.[] | "\(.name)\t\(.vcpus) vCPUs  \(.ram_gb) GiB  EncryptAtHost: \(.encryption_at_host)  AccelNet: \(.accelerated_networking)  ZoneRestrictions: \(.zone_restrictions)"'
else
  RESULT=$(echo "$RAW" | jq -r "${JQ_FILTER} | .name" 2>/dev/null | head -1)

  if [[ -z "$RESULT" ]]; then
    echo "❌ No SKU found matching the given filters in $LOCATION" >&2
    exit 1
  fi

  echo "✅ Found: $RESULT" >&2
  echo "$RESULT"
fi
