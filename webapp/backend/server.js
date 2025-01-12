// server.js
const { DefaultAzureCredential } = require('@azure/identity');
const { BlobServiceClient } = require('@azure/storage-blob');
const jwtDecode = require('jwt-decode');
import jwtDecode from "jwt-decode";

const express = require('express');
const cors = require('cors');

const app = express();
app.use(cors({
  origin: 'http://localhost:5173',
  // You can add other options here, such as methods, credentials, etc.
}));
require('dotenv').config();

// Optional: read container names from environment or define them here
const CONTAINER_NAMES = ['bronze', 'silver', 'gold'];

// This endpoint will list blobs from multiple containers
app.get('/api/blobs', async (req, res) => {
  console.log('Listing blobs...');
  try {
    // 1. Use managed identity credentials or service principal credentials
    // If running in Azure with managed identity, DefaultAzureCredential
    // will automatically pick up the managed identity token.
    const credential = new DefaultAzureCredential();
    const scope = "https://management.azure.com/.default";
  
    // Obtain the token (returns an AccessToken object with 'token' and 'expiresOnTimestamp')
    const tokenResponse = await credential.getToken(scope);
    console.log('Token acquired:', tokenResponse.token);
    const decoded = jwtDecode(tokenResponse.token);

    // Typically, the 'oid' field in the payload is the object ID of the principal
    console.log("Decoded token payload:", decoded);
    console.log("Principal (object) ID:", decoded.oid || decoded.sub || "Not found");



    // 2. Create a BlobServiceClient using the Storage Account name from an env var
    // e.g., process.env.STORAGE_ACCOUNT_NAME = 'myaccount'
    const accountName = process.env.STORAGE_ACCOUNT_NAME; 
    console.log('accountName:', accountName);
    if (!accountName) {
      throw new Error('Missing STORAGE_ACCOUNT_NAME environment variable.');
    }

    const blobServiceClient = new BlobServiceClient(
      `https://${accountName}.blob.core.windows.net`,
      credential
    );

    // 3. For each container, list the blob names
    const result = {};
    for (const containerName of CONTAINER_NAMES) {
      const containerClient = blobServiceClient.getContainerClient(containerName);
      const blobNames = [];

      // List all blobs in this container
      for await (const blob of containerClient.listBlobsFlat()) {
        blobNames.push(blob.name);
      }

      result[containerName] = blobNames;
    }

    // 4. Return a JSON object mapping containerName -> list of blob names
    return res.status(200).json(result);

  } catch (error) {
    console.error('Error listing blobs:', error.message);
    return res.status(500).json({ error: error.message });
  }
});

// (Optional) handle root request (serving your React app if you choose)
app.get('/', (req, res) => {
  res.send('Hello from backend!'); // Or serve the built React bundle
});

// Start the server
const port = process.env.PORT || 8080;
app.listen(port, () => {
  console.log(`Server listening on port ${port}`);
});
