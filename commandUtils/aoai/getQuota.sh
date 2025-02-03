az cognitiveservices account list --subscription "253f778b-553f-4871-b143-123f314c45c1" \
--query "[].{Name:name, Location:location, SKU:skuName, ResourceGroup:resourceGroup, Type:kind}"
