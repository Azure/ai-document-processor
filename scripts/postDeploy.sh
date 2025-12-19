#!/bin/bash
# Post-deploy script for EventGrid subscription
# This runs AFTER code deployment (azd deploy), when the function is fully initialized
#
# This script creates the EventGrid subscription that connects blob uploads to the Function.
# It uses az eventgrid system-topic event-subscription create which is more reliable
# than Bicep deployment for Flex Consumption plans.
#
# KEY INSIGHT: The System Topic must be pre-created in Bicep (main.bicep) so we can use
# az eventgrid system-topic event-subscription create instead of direct storage subscriptions.

echo "========================================"
echo "Post-deploy: EventGrid Subscription"
echo "========================================"

# Load azd environment values
eval $(azd env get-values)

# Configuration from azd environment
RESOURCE_GROUP="${AZURE_RESOURCE_GROUP}"
FUNCTION_APP_NAME="${PROCESSING_FUNCTION_APP_NAME}"
STORAGE_ACCOUNT="${AZURE_STORAGE_ACCOUNT}"
SYSTEM_TOPIC_NAME="${BRONZE_SYSTEM_TOPIC_NAME}"
CONTAINER_NAME="${BRONZE_CONTAINER_NAME:-bronze}"

# Fixed values
FUNCTION_NAME="start_orchestrator_on_blob"
SUBSCRIPTION_NAME="bronze-blob-created-${FUNCTION_NAME}"
SUBJECT_FILTER="/blobServices/default/containers/${CONTAINER_NAME}/"

echo ""
echo "Configuration:"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Function App: $FUNCTION_APP_NAME"
echo "  Storage Account: $STORAGE_ACCOUNT"
echo "  System Topic: $SYSTEM_TOPIC_NAME"
echo "  Container: $CONTAINER_NAME"

# Validate required environment variables
if [ -z "$RESOURCE_GROUP" ] || [ -z "$FUNCTION_APP_NAME" ] || [ -z "$STORAGE_ACCOUNT" ]; then
    echo ""
    echo "ERROR: Missing required environment variables."
    echo "Make sure these are set in your azd environment:"
    echo "  AZURE_RESOURCE_GROUP"
    echo "  PROCESSING_FUNCTION_APP_NAME" 
    echo "  AZURE_STORAGE_ACCOUNT"
    exit 1
fi

if [ -z "$SYSTEM_TOPIC_NAME" ]; then
    echo ""
    echo "ERROR: BRONZE_SYSTEM_TOPIC_NAME not set."
    echo "This should be output from the Bicep deployment."
    echo "Make sure the EventGrid System Topic is defined in main.bicep"
    exit 1
fi
# Get the blobs_extension key for webhook URL
echo ""
echo "Getting blobs_extension key from function app..."
BLOBS_EXTENSION_KEY=$(az functionapp keys list \
    --name "$FUNCTION_APP_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --query "systemKeys.blobs_extension" \
    -o tsv)

if [ -z "$BLOBS_EXTENSION_KEY" ]; then
    echo "ERROR: Could not retrieve blobs_extension key."
    echo "The function app may not be fully initialized yet."
    exit 1
fi

echo "blobs_extension key retrieved successfully."

# Build webhook URL
WEBHOOK_ENDPOINT="https://${FUNCTION_APP_NAME}.azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.${FUNCTION_NAME}&code=${BLOBS_EXTENSION_KEY}"
echo "Webhook URL: ${WEBHOOK_ENDPOINT:0:80}..."

# Check if subscription already exists on the system topic
echo ""
echo "Checking for existing EventGrid subscription..."
EXISTING=$(az eventgrid system-topic event-subscription list \
    --resource-group "$RESOURCE_GROUP" \
    --system-topic-name "$SYSTEM_TOPIC_NAME" \
    --query "[?name=='$SUBSCRIPTION_NAME'].name" \
    -o tsv 2>/dev/null)

if [ -n "$EXISTING" ]; then
    echo "EventGrid subscription '$SUBSCRIPTION_NAME' already exists. Skipping creation."
    exit 0
fi

# Warmup: Hit the function endpoint to wake it up before validation
echo ""
echo "Warming up function to ensure it responds during webhook validation..."
for i in 1 2 3 4 5; do
    echo "  Warmup attempt $i/5..."
    curl -s -X POST -H "Content-Type: application/json" -d "{}" --max-time 60 "$WEBHOOK_ENDPOINT" > /dev/null 2>&1 || true
    sleep 2
done
echo "Warmup complete."

# Create the event subscription using system topic approach
echo ""
echo "Creating EventGrid subscription via System Topic..."
echo "  Subscription: $SUBSCRIPTION_NAME"
echo "  System Topic: $SYSTEM_TOPIC_NAME"
echo "  Subject Filter: $SUBJECT_FILTER"
echo ""

az eventgrid system-topic event-subscription create \
    --name "$SUBSCRIPTION_NAME" \
    --resource-group "$RESOURCE_GROUP" \
    --system-topic-name "$SYSTEM_TOPIC_NAME" \
    --endpoint-type webhook \
    --endpoint "$WEBHOOK_ENDPOINT" \
    --included-event-types Microsoft.Storage.BlobCreated \
    --subject-begins-with "$SUBJECT_FILTER"

if [ $? -eq 0 ]; then
    echo ""
    echo "========================================"
    echo "EventGrid subscription created successfully!"
    echo "========================================"
    echo ""
    echo "Blob uploads to 'bronze' container will now trigger the function."
    echo ""
    
    # Upload test blob to trigger the function
    echo "Uploading test blob to trigger function..."
    az storage blob upload --account-name "$STORAGE_ACCOUNT" --container-name "$CONTAINER_NAME" --name role_library-3.pdf --file ./data/role_library-3.pdf --auth-mode login --overwrite
    
    if [ $? -eq 0 ]; then
        echo "Test blob uploaded successfully. Check function logs for processing."
    else
        echo "Warning: Test blob upload failed, but EventGrid subscription is active."
    fi
else
    echo ""
    echo "========================================"
    echo "ERROR: Failed to create EventGrid subscription"
    echo "========================================"
    echo ""
    echo "This can happen if the function cold start exceeds webhook validation timeout."
    echo ""
    echo "MANUAL WORKAROUND:"
    echo "  1. Go to Azure Portal"
    echo "  2. Navigate to: Storage Account '$STORAGE_ACCOUNT' > Events"
    echo "  3. Click '+ Event Subscription'"
    echo "  4. Configure:"
    echo "     - Name: $SUBSCRIPTION_NAME"
    echo "     - Event Types: Blob Created"
    echo "     - Endpoint Type: Web Hook"
    echo "     - Endpoint: (get from Function App > Functions > $FUNCTION_NAME > Get function URL)"
    echo "     - Subject Filters: Begins with '$SUBJECT_FILTER'"
    echo ""
    echo "See: docs/FLEX-CONSUMPTION-EVENTGRID-PROBLEM.md"
    # Don't exit with error - deployment is still usable, just needs manual step
    exit 0
fi