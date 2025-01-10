import React, { useEffect, useState } from 'react';
import { Button, Card, CardContent, Typography, Box, List, ListItem, ListItemText } from '@mui/material';

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
      // Call our Node server endpoint (assumes same domain; adjust if different)
      const response = await fetch('http://localhost:8080/api/blobs');
      if (!response.ok) {
        throw new Error(`Error: ${response.status} - ${response.statusText}`);
      }

      // This should return an object: { bronze: [...], silver: [...], gold: [...] }
      const data = await response.json();
      setBlobsByContainer(data);
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
                      <ListItemText
                        primary={blobName}
                        primaryTypographyProps={{ align: 'center' }}
                      />
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