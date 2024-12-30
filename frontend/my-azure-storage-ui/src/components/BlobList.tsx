import React, { useEffect, useState } from 'react';
import { Button, Card, CardContent, Typography, Box, List, ListItem, ListItemText } from '@mui/material';
import { BlobServiceClient } from '@azure/storage-blob';

interface BlobItemInfo {
  name: string;
  containerName: string;
}

// For a real project, store this in .env and reference process.env.REACT_APP_STORAGE_CONNECTION_STRING
const AZURE_STORAGE_CONNECTION_STRING = 'BlobEndpoint=https://azfunctionsyziy6wu4gytru.blob.core.windows.net/;QueueEndpoint=https://azfunctionsyziy6wu4gytru.queue.core.windows.net/;FileEndpoint=https://azfunctionsyziy6wu4gytru.file.core.windows.net/;TableEndpoint=https://azfunctionsyziy6wu4gytru.table.core.windows.net/;SharedAccessSignature=sv=2022-11-02&ss=bfqt&srt=sco&sp=rwdlacupiyx&se=2025-03-01T01:37:35Z&st=2024-12-28T17:37:35Z&spr=https&sig=BDL0bKH4XWOgmtX4UADnG3IJHo%2BCXe%2B2whJujg4vm9o%3D'

// The containers we always want to display
const CONTAINER_NAMES = ['bronze', 'silver', 'gold'];

const BlobList: React.FC = () => {
  const [blobsByContainer, setBlobsByContainer] = useState<Record<string, string[]>>({
    bronze: [],
    silver: [],
    gold: [],
  });

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const fetchBlobsFromAllContainers = async () => {
    setLoading(true);
    setError(null);

    try {
      const blobServiceClient = BlobServiceClient.fromConnectionString(
        AZURE_STORAGE_CONNECTION_STRING
      );

      // Prepare an object to collect blob names by container
      const newBlobsByContainer: Record<string, string[]> = {
        bronze: [],
        silver: [],
        gold: [],
      };

      // For each of the containers we care about, list blobs
      for (const containerName of CONTAINER_NAMES) {
        const containerClient = blobServiceClient.getContainerClient(containerName);

        try {
          // Iterate over all blobs in this container
          const blobNames: string[] = [];
          for await (const blob of containerClient.listBlobsFlat()) {
            blobNames.push(blob.name);
          }
          // Store the results
          newBlobsByContainer[containerName] = blobNames;
        } catch (e) {
          // If the container doesn't exist or is inaccessible, you can handle it here
          console.warn(`Error fetching blobs for ${containerName}: ${(e as Error).message}`);
        }
      }

      setBlobsByContainer(newBlobsByContainer);
    } catch (err: any) {
      console.error('Error fetching blobs:', err);
      setError(`Error: ${err.message || 'Unknown error'}`);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchBlobsFromAllContainers();
  }, []);

  const handleRefresh = () => {
    fetchBlobsFromAllContainers();
  };

  return (
    <div style={{ padding: '1rem', border: '1px solid #ddd', borderRadius: '4px' }}>
      <Typography variant="h5" gutterBottom>
        Blob Viewer
      </Typography>
      <Box marginBottom={2}>
        <Button
          variant="contained"
          color="secondary"
          onClick={handleRefresh}
          disabled={loading}
        >
          {loading ? 'Refreshing...' : 'Refresh'}
        </Button>
      </Box>

      {error && (
        <Typography variant="body1" color="error" gutterBottom>
          {error}
        </Typography>
      )}

      {/* Render a single "tile" (Card) per container */}
      {CONTAINER_NAMES.map((containerName) => {
        const blobNames = blobsByContainer[containerName] || [];
        return (
          <Card key={containerName} sx={{ marginBottom: 2 }}>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                Container: {containerName}
              </Typography>

              {blobNames.length === 0 ? (
                <Typography variant="body2">No files present</Typography>
              ) : (
                <List dense>
                  {blobNames.map((blobName) => (
                    <ListItem key={blobName} disablePadding>
                      <ListItemText primary={blobName} primaryTypographyProps={{ align: 'center' }} />
                    </ListItem>
                  ))}
                </List>
              )}
            </CardContent>
          </Card>
        );
      })}
    </div>
  );
};

export default BlobList;
