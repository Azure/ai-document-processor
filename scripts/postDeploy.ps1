# PowerShell post-deploy script for EventGrid subscription
# This runs AFTER code deployment (azd deploy), when the function is fully initialized
#
# This script follows the pattern from Microsoft's official quickstart:
# https://github.com/Azure-Samples/functions-quickstart-python-azd-eventgrid-blob
#
# KEY INSIGHT: Using `az eventgrid system-topic event-subscription create` is more reliable
# than creating a subscription directly on the storage account because:
# 1. The System Topic is pre-created in Bicep (more reliable than auto-creation)
# 2. The CLI command has better timeout/retry behavior for webhook validation

Write-Host "========================================"
Write-Host "Post-deploy: EventGrid Subscription"
Write-Host "========================================"

# Check for required tools
$tools = @("az", "azd")
foreach ($tool in $tools) {
    if (!(Get-Command $tool -ErrorAction SilentlyContinue)) {
        Write-Host "Error: $tool command line tool is not available, check pre-requisites in README.md"
        exit 1
    }
}

# Load azd environment values (using the pattern from Microsoft's quickstart)
Write-Host "Loading azd .env file from current environment..."
foreach ($line in (& azd env get-values)) {
    if ($line -match "([^=]+)=(.*)") {
        $key = $matches[1]
        $value = $matches[2] -replace '^"|"$'
        [Environment]::SetEnvironmentVariable($key, $value)
    }
}

$resourceGroup = $env:AZURE_RESOURCE_GROUP
if (-not $resourceGroup) { $resourceGroup = $env:RESOURCE_GROUP }
$functionAppName = $env:PROCESSING_FUNCTION_APP_NAME
if (-not $functionAppName) { $functionAppName = $env:FUNCTION_APP_NAME }
$systemTopicName = $env:BRONZE_SYSTEM_TOPIC_NAME
$containerName = $env:BRONZE_CONTAINER_NAME
if (-not $containerName) { $containerName = "bronze" }
$subscriptionName = "bronze-blob-trigger"
$functionName = "start_orchestrator_on_blob"

Write-Host ""
Write-Host "Configuration:"
Write-Host "  Resource Group: $resourceGroup"
Write-Host "  Function App: $functionAppName"
Write-Host "  System Topic: $systemTopicName"
Write-Host "  Container: $containerName"
Write-Host "  Function Name: $functionName"
Write-Host "  Subscription Name: $subscriptionName"

# Check if subscription already exists on the system topic
Write-Host ""
Write-Host "Checking for existing EventGrid subscription..."
$existingSubs = az eventgrid system-topic event-subscription list -g $resourceGroup --system-topic-name $systemTopicName --query "[?name=='$subscriptionName'].name" -o tsv 2>$null

if ($existingSubs -eq $subscriptionName) {
    Write-Host "EventGrid subscription '$subscriptionName' already exists. Skipping creation."
    Write-Host "========================================"
    exit 0
}

# Get the blobs_extension key
Write-Host ""
Write-Host "Getting blobs_extension key from function app..."
$blobsExtensionKey = az functionapp keys list --name $functionAppName --resource-group $resourceGroup --query "systemKeys.blobs_extension" -o tsv

if (-not $blobsExtensionKey) {
    Write-Host "ERROR: Could not retrieve blobs_extension key."
    Write-Host "The function app may not be fully initialized yet."
    Write-Host ""
    Write-Host "This can happen if:"
    Write-Host "  1. The function code hasn't been deployed yet"
    Write-Host "  2. The blob trigger function hasn't initialized"
    Write-Host ""
    Write-Host "Try running 'azd deploy' again, or wait a few minutes and run this script manually."
    exit 1
}

Write-Host "blobs_extension key retrieved successfully."

# Build webhook URL (using triple quotes for proper escaping in az CLI - same as quickstart)
$endpointUrl = """https://$functionAppName.azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.$functionName&code=$blobsExtensionKey"""

# Build filter for bronze container
$filter = "/blobServices/default/containers/$containerName/"

# Warm up the function to prevent cold start timeout during webhook validation
Write-Host ""
Write-Host "Warming up the function (to prevent cold start timeout)..."
for ($i = 1; $i -le 3; $i++) {
    try {
        $null = Invoke-WebRequest -Uri "https://$functionAppName.azurewebsites.net/" -TimeoutSec 120 -ErrorAction SilentlyContinue
        Write-Host "  Warmup $i/3 complete"
    } catch {
        Write-Host "  Warmup $i/3 - Function waking up..."
    }
    Start-Sleep -Seconds 5
}

# Create the Event Grid subscription using system-topic command (more reliable than direct storage subscription)
Write-Host ""
Write-Host "Creating EventGrid subscription on System Topic..."
Write-Host "  System Topic: $systemTopicName"
Write-Host "  Endpoint: https://$functionAppName.azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.$functionName"
Write-Host "  Filter: $filter"
Write-Host ""

$result = az eventgrid system-topic event-subscription create `
    -n $subscriptionName `
    -g $resourceGroup `
    --system-topic-name $systemTopicName `
    --endpoint-type webhook `
    --endpoint $endpointUrl `
    --included-event-types Microsoft.Storage.BlobCreated `
    --subject-begins-with $filter `
    2>&1

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "========================================"
    Write-Host "SUCCESS: EventGrid subscription created!"
    Write-Host "========================================"
    Write-Host ""
    Write-Host "Your blob trigger is now active. When you upload a file to the"
    Write-Host "'$containerName' container, it will automatically trigger the function."
    exit 0
} else {
    Write-Host ""
    Write-Host "========================================"
    Write-Host "ERROR: Failed to create EventGrid subscription"
    Write-Host "========================================"
    Write-Host ""
    Write-Host "Error details:"
    Write-Host $result
    Write-Host ""
    Write-Host "This can happen due to webhook validation timeout on Flex Consumption."
    Write-Host ""
    Write-Host "MANUAL WORKAROUND:"
    Write-Host "  1. Go to Azure Portal"
    Write-Host "  2. Navigate to: Storage Account > Events > Event Subscriptions"
    Write-Host "  3. Click '+ Event Subscription'"
    Write-Host "  4. Configure:"
    Write-Host "     - Name: $subscriptionName"
    Write-Host "     - System Topic: $systemTopicName"
    Write-Host "     - Event Types: Blob Created"
    Write-Host "     - Endpoint Type: Azure Function"
    Write-Host "     - Endpoint: Select your function app > $functionName"
    Write-Host "     - Filters > Subject Begins With: $filter"
    Write-Host ""
    Write-Host "See: docs/FLEX-CONSUMPTION-EVENTGRID-TROUBLESHOOTING-LOG.md"
    # Don't fail the deployment - manual step can be done later
    exit 0
}
