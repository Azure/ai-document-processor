curl -X POST http://localhost:7071/api/client \
  -H "Content-Type: application/json" \
  -d '{
    "blobs": [
      {
        "name": "bronze/sample1.pdf",
        "url": "https://<storage_account>.blob.core.windows.net/bronze/role_library-3.pdf?<SAS_token>",
        "container": "bronze"
      }
    ]
  }'