#!/bin/bash

# Troubleshooting script for Azure Function App in private network
# Run this script from your VM inside the virtual network

set -e

# Function App details from your debug.log
FUNCTION_APP_NAME="func-processing-vwlecyttb6bcs"
FUNCTION_APP_URL="https://${FUNCTION_APP_NAME}.azurewebsites.net"

echo "=== Azure Function App Troubleshooting ==="
echo "Function App: $FUNCTION_APP_NAME"
echo "URL: $FUNCTION_APP_URL"
echo ""

# Test 1: DNS Resolution
echo "1. Testing DNS Resolution..."
echo "----------------------------"
nslookup $FUNCTION_APP_NAME.azurewebsites.net || echo "❌ DNS resolution failed"
echo ""

# Test 2: Network Connectivity
echo "2. Testing Network Connectivity..."
echo "-----------------------------------"
# Test basic connectivity
nc -zv $FUNCTION_APP_NAME.azurewebsites.net 443 2>&1 && echo "✅ Port 443 is reachable" || echo "❌ Port 443 is not reachable"
echo ""

# Test 3: Function App Health
echo "3. Testing Function App Health..."
echo "----------------------------------"
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" $FUNCTION_APP_URL || echo "❌ Function App is not responding"
echo ""

# Test 4: Admin Endpoints (requires master key)
echo "4. Testing Admin Endpoints..."
echo "------------------------------"
echo "Note: Admin endpoints require authentication. If you have the master key, you can test:"
echo "curl -H 'x-functions-key: YOUR_MASTER_KEY' $FUNCTION_APP_URL/admin/functions"
echo ""

# Test 5: Function Discovery
echo "5. Testing Function Discovery..."
echo "--------------------------------"
echo "Testing available endpoints:"

# Test the main HTTP function
echo "Testing /api/client endpoint:"
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" $FUNCTION_APP_URL/api/client || echo "❌ /api/client endpoint failed"

# Test root API
echo "Testing /api/ endpoint:"
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" $FUNCTION_APP_URL/api/ || echo "❌ /api/ endpoint failed"

echo ""

# Test 6: Check if SCM site is accessible (Kudu)
echo "6. Testing SCM Site (Kudu)..."
echo "------------------------------"
SCM_URL="https://${FUNCTION_APP_NAME}.scm.azurewebsites.net"
echo "SCM URL: $SCM_URL"
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" $SCM_URL || echo "❌ SCM site is not accessible from private network"
echo ""

# Test 7: Check Function Runtime Status
echo "7. Testing Function Runtime Status..."
echo "--------------------------------------"
echo "Testing runtime status endpoint:"
curl -s -o /dev/null -w "HTTP Status: %{http_code}\n" $FUNCTION_APP_URL/admin/host/status || echo "❌ Runtime status endpoint failed"
echo ""

echo "=== Troubleshooting Complete ==="
echo ""
echo "Next steps if functions are not visible:"
echo "1. If DNS resolution fails, check private DNS zone configuration"
echo "2. If connectivity fails, check NSG and firewall rules"
echo "3. If admin endpoints fail, the functions might not be properly deployed"
echo "4. Check Azure Portal for function deployment status"
echo "5. Review Function App logs in Azure Portal"
