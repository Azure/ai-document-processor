# Troubleshooting script for Azure Function App in private network
# Run this script from your VM inside the virtual network

# Function App details from your debug.log
$FUNCTION_APP_NAME = "func-processing-vwlecyttb6bcs"
$FUNCTION_APP_URL = "https://$FUNCTION_APP_NAME.azurewebsites.net"

Write-Host "=== Azure Function App Troubleshooting ===" -ForegroundColor Yellow
Write-Host "Function App: $FUNCTION_APP_NAME"
Write-Host "URL: $FUNCTION_APP_URL"
Write-Host ""

# Test 1: DNS Resolution
Write-Host "1. Testing DNS Resolution..." -ForegroundColor Green
Write-Host "----------------------------"
try {
    $dnsResult = Resolve-DnsName "$FUNCTION_APP_NAME.azurewebsites.net" -ErrorAction Stop
    Write-Host "✅ DNS Resolution successful. IP: $($dnsResult.IPAddress -join ', ')" -ForegroundColor Green
} catch {
    Write-Host "❌ DNS resolution failed: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Test 2: Network Connectivity
Write-Host "2. Testing Network Connectivity..." -ForegroundColor Green
Write-Host "-----------------------------------"
try {
    $tcpTest = Test-NetConnection -ComputerName "$FUNCTION_APP_NAME.azurewebsites.net" -Port 443 -WarningAction SilentlyContinue
    if ($tcpTest.TcpTestSucceeded) {
        Write-Host "✅ Port 443 is reachable" -ForegroundColor Green
    } else {
        Write-Host "❌ Port 443 is not reachable" -ForegroundColor Red
    }
} catch {
    Write-Host "❌ Network connectivity test failed: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Test 3: Function App Health
Write-Host "3. Testing Function App Health..." -ForegroundColor Green
Write-Host "----------------------------------"
try {
    $response = Invoke-WebRequest -Uri $FUNCTION_APP_URL -Method GET -UseBasicParsing -ErrorAction Stop
    Write-Host "✅ Function App is responding. Status: $($response.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "❌ Function App is not responding: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Test 4: Function Discovery
Write-Host "4. Testing Function Discovery..." -ForegroundColor Green
Write-Host "--------------------------------"

# Test the main HTTP function
Write-Host "Testing /api/client endpoint:"
try {
    $response = Invoke-WebRequest -Uri "$FUNCTION_APP_URL/api/client" -Method GET -UseBasicParsing -ErrorAction Stop
    Write-Host "✅ /api/client endpoint responding. Status: $($response.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "❌ /api/client endpoint failed: $($_.Exception.Message)" -ForegroundColor Red
}

# Test API root
Write-Host "Testing /api/ endpoint:"
try {
    $response = Invoke-WebRequest -Uri "$FUNCTION_APP_URL/api/" -Method GET -UseBasicParsing -ErrorAction Stop
    Write-Host "✅ /api/ endpoint responding. Status: $($response.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "❌ /api/ endpoint failed: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# Test 5: Check if SCM site is accessible (Kudu)
Write-Host "5. Testing SCM Site (Kudu)..." -ForegroundColor Green
Write-Host "------------------------------"
$SCM_URL = "https://$FUNCTION_APP_NAME.scm.azurewebsites.net"
Write-Host "SCM URL: $SCM_URL"
try {
    $response = Invoke-WebRequest -Uri $SCM_URL -Method GET -UseBasicParsing -ErrorAction Stop
    Write-Host "✅ SCM site is accessible. Status: $($response.StatusCode)" -ForegroundColor Green
} catch {
    Write-Host "❌ SCM site is not accessible from private network: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

Write-Host "=== Troubleshooting Complete ===" -ForegroundColor Yellow
Write-Host ""
Write-Host "Next steps if functions are not visible:" -ForegroundColor Cyan
Write-Host "1. If DNS resolution fails, check private DNS zone configuration"
Write-Host "2. If connectivity fails, check NSG and firewall rules"
Write-Host "3. If admin endpoints fail, the functions might not be properly deployed"
Write-Host "4. Check Azure Portal for function deployment status"
Write-Host "5. Review Function App logs in Azure Portal"
