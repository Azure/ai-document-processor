import React, { useState, useEffect } from 'react';
import { BlobServiceClient } from '@azure/storage-blob';

interface BlobItem {
  name: string;
}

// For development, keep this as a hardcoded string (move to .env for production)
const AZURE_STORAGE_CONNECTION_STRING = '<YOUR_CONNECTION_STRING>';
const CONTAINER_NAME = '<YOUR_CONTAINER_NAME>'; // Replace with your container name

const BlobList: React.FC = () => {
  const [blobs, setBlobs] = useState<BlobItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchBlobs = async () => {
    setLoading(true);
    setError(null);

    try {
      const blobServiceClient = BlobServiceClient.fromConnectionString(
        AZURE_STORAGE_CONNECTION_STRING
      );

      const containerClient = blobServiceClient.getContainerClient(CONTAINER_NAME);

      const blobItems: BlobItem[] = [];
      for await (const blob of containerClient.listBlobsFlat()) {
        blobItems.push({ name: blob.name });
      }

      setBlobs(blobItems);
    } catch (err: any) {
      console.error('Error fetching blobs:', err);
      setError(`Failed to fetch blobs: ${err.message || 'Unknown error'}`);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchBlobs();
  }, []);

  return (
    <div>
      <h2>Blobs in Container: {CONTAINER_NAME}</h2>

      {loading && <p>Loading...</p>}
      {error && <p style={{ color: 'red' }}>{error}</p>}
      {!loading && !error && blobs.length === 0 && <p>No blobs found in the container.</p>}

      <ul>
        {blobs.map((blob) => (
          <li key={blob.name}>{blob.name}</li>
        ))}
      </ul>
    </div>
  );
};

export default BlobList;
