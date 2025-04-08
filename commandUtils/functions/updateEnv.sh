RESOURCE_GROUP_NAME="rg-demo"
FUNCTION_APP_NAME="processing-dbfbvcgqgrid6"


az functionapp config appsettings set \
  --name $FUNCTION_APP_NAME \
  --resource-group $RESOURCE_GROUP_NAME \
  --settings SCM_DO_BUILD_DURING_DEPLOYMENT="true" ENABLE_ORYX_BUILD="true"


az functionapp config appsettings set \
  --name processing-dbfbvcgqgrid6 \
  --resource-group rg-demo \
  --settings SCM_DO_BUILD_DURING_DEPLOYMENT="true" ENABLE_ORYX_BUILD="true"


az functionapp config appsettings delete \
  --name processing-dbfbvcgqgrid6 \
  --resource-group rg-demo \
  --setting-names BUILD_FLAGS

  az functionapp config appsettings delete \
  --name processing-dbfbvcgqgrid6 \
  --resource-group rg-demo \
  --setting-names XDG_CACHE_HOME