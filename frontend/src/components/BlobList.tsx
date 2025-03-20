import React, { useEffect, useState } from 'react';
import { Button, Card, CardContent, Typography, Box, List, ListItem, ListItemText, Link, Checkbox } from '@mui/material';

const CONTAINER_NAMES = ['bronze', 'silver', 'gold'];

// const baseFunctionUrl = process.env.REACT_APP_FUNCTION_URL;
// console.log("baseFunctionUrl", baseFunctionUrl)

const functionUrl = `/api/app_getBlobsByContainer`;

interface BlobItem {
  name: string;
  url: string;
}

export interface SelectedBlob extends BlobItem {
  container: string;
}

interface BlobListProps {
  onSelectionChange?: (selected: SelectedBlob[]) => void;
}


const BlobList: React.FC<BlobListProps> = ( {onSelectionChange}) => {
  const [blobsByContainer, setBlobsByContainer] = useState<Record<string, BlobItem[]>>({
    bronze: [],
    silver: [],
    gold: [],
  });

  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const [selectedBlobs, setSelectedBlobs] = useState<SelectedBlob[]>([]);
  
  const fetchBlobsFromAllContainers = async () => {
    setLoading(true);
    setError(null);

    try {
      const response = await fetch(functionUrl); // Adjust API URL if needed
      console.log("response", response)

      if (!response.ok) {
        throw new Error(`Error: ${response.status} - ${response.statusText}`);
      }

      const data: Record<string, BlobItem[]> = await response.json();
      setBlobsByContainer(data);
    } catch (err: unknown) {
      if (err instanceof Error) {
        setError(`Error: ${err.message || 'Unknown error'}`);
      }
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchBlobsFromAllContainers();
  }, []);


  // Toggle selection for a blob file
  const toggleSelection = (container: string, blob: BlobItem) => {
    const exists = selectedBlobs.some(
      (b) => b.name === blob.name && b.container === container
    );
    let newSelection: SelectedBlob[];
    if (exists) {
      newSelection = selectedBlobs.filter(
        (b) => !(b.name === blob.name && b.container === container)
      );
    } else {
      newSelection = [...selectedBlobs, { ...blob, container }];
    }
    setSelectedBlobs(newSelection);
    
    if (onSelectionChange) {
      onSelectionChange(newSelection);
    }
  };

  return (
    <div style={{ padding: '1rem', border: '1px solid #ddd', borderRadius: '4px' }}>
      <Typography variant="h5" gutterBottom>
        Blob Viewer
      </Typography>
      <Box marginBottom={2}>
        <Button variant="contained" color="secondary" onClick={fetchBlobsFromAllContainers} disabled={loading}>
          {loading ? 'Refreshing...' : 'Refresh'}
        </Button>
      </Box>

      {error && (
        <Typography variant="body1" color="error" gutterBottom>
          {error}
        </Typography>
      )}

      {CONTAINER_NAMES.map((containerName) => {
        const blobItems = blobsByContainer[containerName] || [];
        return (
          <Card key={containerName} sx={{ marginBottom: 2 }}>
            <CardContent>
              <Typography variant="h6" gutterBottom>
                Container: {containerName}
              </Typography>
              {blobItems.length === 0 ? (
                <Typography variant="body2">No files present</Typography>
              ) : (
                <List dense>
                  {blobItems.map((blob) => (
                    <ListItem key={blob.name} disablePadding>
                      <Checkbox
                        checked={selectedBlobs.some(
                          (b) => b.name === blob.name && b.container === containerName
                        )}
                        onChange={() => toggleSelection(containerName, blob)}
                      />
                      
                      <ListItemText
                        primary={
                          <Link href={blob.url} target="_blank" rel="noopener noreferrer">
                            {blob.name}
                          </Link>
                        }
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
