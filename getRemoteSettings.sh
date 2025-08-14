eval $(azd env get-values)

cd ./pipeline
func azure functionapp fetch-app-settings $PROCESSING_FUNCTION_APP_NAME --decrypt

func settings decrypt
