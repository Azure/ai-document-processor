# Common Issues

1. Azure functions don't show up in portal
- Description: azd deploy executes successfully in the terminal, but the functions are not found in the Azure portal
Troubleshooting Steps
- The issue could be that your function is unable to authenticate to the default blob storage account
- Check the log stream - are there any authorization issues?
- Check the networking of the Storage account - is public access is enabled?
- Check environment vars, is the storage account named correclty?
- Ensure that you are not deploying a local.settings.json with your function package
- Check to ensure that your function app's managed identity has Storage Blob Data Owner or Contributor (add manually if necessary)


"2025-08-08T21:03:05Z   [Warning]   Error response [991829f9-8ce5-415f-a7e5-5d26086b4183] 404 The specified queue does not exist. (00.1s)
Server:Windows-Azure-Queue/1.0 Microsoft-HTTPAPI/2.0
x-ms-request-id:9e809390-f003-0052-78a7-08c575000000
x-ms-client-request-id:991829f9-8ce5-415f-a7e5-5d26086b4183
x-ms-version:2025-05-05
x-ms-error-code:QueueNotFound
Date:Fri, 08 Aug 2025 21:03:05 GMT
Content-Length:217
Content-Type:application/xml"

- Ensure you add the S