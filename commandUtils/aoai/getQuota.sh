az cognitiveservices account list --subscription "" \
--query "[].{Name:name, Location:location, SKU:skuName, ResourceGroup:resourceGroup, Type:kind}"
