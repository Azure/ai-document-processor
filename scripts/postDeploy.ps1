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

# Wait for function app to be ready before attempting to get the key
Write-Host ""
Write-Host "Waiting for function app to be ready..."
$maxWaitTime = 300  # 5 minutes total
$waitInterval = 10  # Check every 10 seconds
$elapsedTime = 0
$functionReady = $false

while ($elapsedTime -lt $maxWaitTime -and -not $functionReady) {
    try {
        $status = az functionapp show --name $functionAppName --resource-group $resourceGroup --query "state" -o tsv 2>$null
        if ($status -eq "Running") {
            # Try to ping the function app
            try {
                $response = Invoke-WebRequest -Uri "https://$functionAppName.azurewebsites.net" -TimeoutSec 30 -ErrorAction Stop -UseBasicParsing
                $functionReady = $true
                Write-Host "✓ Function app is ready"
            } catch {
                Write-Host "  Function app is running but not yet responding ($elapsedTime/$maxWaitTime seconds)..."
            }
        } else {
            Write-Host "  Function app state: $status ($elapsedTime/$maxWaitTime seconds)..."
        }
    } catch {
        Write-Host "  Waiting for function app... ($elapsedTime/$maxWaitTime seconds)..."
    }
    
    if (-not $functionReady) {
        Start-Sleep -Seconds $waitInterval
        $elapsedTime += $waitInterval
    }
}

if (-not $functionReady) {
    Write-Host "WARNING: Function app may not be fully ready, but continuing anyway..." -ForegroundColor Yellow
}

# Get the blobs_extension key with retry logic
Write-Host ""
Write-Host "Getting blobs_extension key from function app..."
$blobsExtensionKey = $null
$maxRetries = 6
$retryDelay = 15  # seconds

for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
    try {
        Write-Host "  Attempt $attempt/$maxRetries..."
        $blobsExtensionKey = az functionapp keys list `
            --name $functionAppName `
            --resource-group $resourceGroup `
            --query "systemKeys.blobs_extension" `
            -o tsv 2>&1
        
        # Check if we got a valid key (not an error message)
        if ($blobsExtensionKey -and $blobsExtensionKey -notmatch "error|Error|ERROR" -and $blobsExtensionKey.Trim().Length -gt 0) {
            Write-Host "✓ blobs_extension key retrieved successfully."
            break
        }
        
        if ($attempt -lt $maxRetries) {
            Write-Host "  Key not available yet. Waiting $retryDelay seconds before retry..."
            Start-Sleep -Seconds $retryDelay
            # Exponential backoff
            $retryDelay = [Math]::Min($retryDelay * 1.5, 60)
        }
    } catch {
        if ($attempt -lt $maxRetries) {
            Write-Host "  Error retrieving key: $($_.Exception.Message). Retrying in $retryDelay seconds..."
            Start-Sleep -Seconds $retryDelay
            $retryDelay = [Math]::Min($retryDelay * 1.5, 60)
        } else {
            Write-Host "  Final attempt failed: $($_.Exception.Message)"
        }
    }
}

if (-not $blobsExtensionKey -or $blobsExtensionKey -match "error|Error|ERROR" -or $blobsExtensionKey.Trim().Length -eq 0) {
    Write-Host ""
    Write-Host "ERROR: Could not retrieve blobs_extension key after $maxRetries attempts." -ForegroundColor Red
    Write-Host ""
    Write-Host "This can happen if:" -ForegroundColor Yellow
    Write-Host "  1. The function app hasn't fully initialized yet (common with Flex Consumption)"
    Write-Host "  2. The blob trigger extension hasn't been activated"
    Write-Host "  3. The function code hasn't been fully deployed"
    Write-Host ""
    Write-Host "SOLUTIONS:" -ForegroundColor Cyan
    Write-Host "  1. Wait 5-10 minutes and run this script manually:" -ForegroundColor White
    Write-Host "     pwsh scripts/postDeploy.ps1" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  2. Or create the EventGrid subscription manually via Azure Portal:" -ForegroundColor White
    Write-Host "     a. Go to Azure Portal > Storage Account > Events" -ForegroundColor Gray
    Write-Host "     b. Click '+ Event Subscription'" -ForegroundColor Gray
    Write-Host "     c. Configure:" -ForegroundColor Gray
    Write-Host "        - Name: $subscriptionName" -ForegroundColor Gray
    Write-Host "        - System Topic: $systemTopicName" -ForegroundColor Gray
    Write-Host "        - Event Types: Blob Created" -ForegroundColor Gray
    Write-Host "        - Endpoint Type: Azure Function" -ForegroundColor Gray
    Write-Host "        - Endpoint: Select '$functionAppName' > '$functionName'" -ForegroundColor Gray
    Write-Host "        - Filters > Subject Begins With: $filter" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  3. Or use Azure CLI with Function endpoint (alternative method):" -ForegroundColor White
    Write-Host "     First, get the function key:" -ForegroundColor Gray
    Write-Host "     \$funcKey = az functionapp keys list -n $functionAppName -g $resourceGroup --query functionKeys.default -o tsv" -ForegroundColor Gray
    Write-Host "     Then create subscription with manual endpoint URL" -ForegroundColor Gray
    Write-Host ""
    Write-Host "The deployment succeeded, but the EventGrid subscription needs to be created manually." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "You can run this script again later when the function app is fully initialized:" -ForegroundColor Cyan
    Write-Host "  pwsh scripts/postDeploy.ps1" -ForegroundColor White
    Write-Host ""
    # Exit with 0 to allow deployment to succeed - EventGrid can be set up manually
    exit 0
}

Write-Host "blobs_extension key retrieved successfully."

# Build webhook URL (using triple quotes for proper escaping in az CLI - same as quickstart)
# Format: https://{functionApp}.azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.{functionName}&code={blobs_extension_key}
$endpointUrl = """https://$functionAppName.azurewebsites.net/runtime/webhooks/blobs?functionName=Host.Functions.$functionName&code=$blobsExtensionKey"""
Write-Host "  Using webhook endpoint with blobs_extension key"

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
Write-Host "  Event Type: Microsoft.Storage.BlobCreated"
Write-Host ""

# Add a small delay before creating subscription to ensure function is ready
Write-Host "Waiting 10 seconds to ensure function is fully ready..."
Start-Sleep -Seconds 10

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
    Write-Host ""
    
    # Upload test blob to trigger the function
    Write-Host "Uploading test blob to trigger function..."
    $storageAccount = $env:AZURE_STORAGE_ACCOUNT
    az storage blob upload --account-name $storageAccount --container-name $containerName --name role_library-3.pdf --file ./data/role_library-3.pdf --auth-mode login --overwrite
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "Test blob uploaded successfully. Check function logs for processing."
    } else {
        Write-Host "Warning: Test blob upload failed, but EventGrid subscription is active."
    }
    
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
