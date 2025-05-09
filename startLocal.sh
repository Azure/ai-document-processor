# Get local settings from the remote environment


eval $(azd env get-values)

cd web-backend
func azure functionapp fetch-app-settings $WEB_BACKEND_FUNCTION_APP_NAME

func start --build

# cd ../pipeline
# func azure functionapp fetch-app-settings $PROCESSING_FUNCTION_APP_NAME
# func start --build

