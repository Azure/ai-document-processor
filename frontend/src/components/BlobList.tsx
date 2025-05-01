import React, { useEffect, useState } from 'react';
import { 
  Button, Card, CardContent, Typography, Box, List, ListItem, 
  ListItemText, Link, Checkbox
} from '@mui/material';
import BlobUploader from './BlobUploader';
import DeleteButton from './DeleteButton';

const CONTAINER_NAMES = ['bronze', 'silver', 'gold'];

// const baseFunctionUrl = process.env.REACT_APP_FUNCTION_URL;
// console.log("baseFunctionUrl", baseFunctionUrl)

const getBlobsUrl = `/api/getBlobsByContainer`;
const deleteBlobsUrl = `/api/deleteBlobs`;

export interface BlobItem {
  container: string;
  name: string;
  url: string;
}

interface BlobListProps {
  onSelectionChange?: (selected: BlobItem[]) => void;
}

const BlobList: React.FC<BlobListProps> = ({ onSelectionChange }) => {
  const [blobsByContainer, setBlobsByContainer] = useState<Record<string, BlobItem[]>>({
    bronze: [],
    silver: [],
    gold: [],
  });

  const [refreshLoading, setRefreshLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [deleteLoading, setDeleteLoading] = useState(false);
  const [selectedBlobs, setSelectedBlobs] = useState<BlobItem[]>([]);
  
  const fetchBlobsFromAllContainers = async () => {
    setRefreshLoading(true);
    setError(null);

    try {
      const response = await fetch(getBlobsUrl);
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
      setRefreshLoading(false);
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
    let newSelection: BlobItem[];
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

  // Handle delete confirmation
  const handleDeleteConfirm = async () => {
    setDeleteLoading(true);

    try {
      const response = await fetch(deleteBlobsUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ blobs: selectedBlobs }),
      });

      if (!response.ok) {
        throw new Error(`Error: ${response.status} - ${response.statusText}`);
      }

      const result = await response.json();
      
      if (result.failed && result.failed.length > 0) {
        setError(`Failed to delete ${result.failed.length} blobs. Successfully deleted ${result.success.length} blobs.`);
      }

      // Clear selection and refresh the list
      setSelectedBlobs([]);
      if (onSelectionChange) {
        onSelectionChange([]);
      }
      fetchBlobsFromAllContainers();
    } catch (err: unknown) {
      if (err instanceof Error) {
        setError(`Error during deletion: ${err.message}`);
      }
    } finally {
      setDeleteLoading(false);
    }
  };

  // Handle successful upload
  const handleUploadSuccess = () => {
    fetchBlobsFromAllContainers();
  };

  return (
    <div style={{ padding: '1rem', border: '1px solid #ddd', borderRadius: '4px' }}>
      <Typography variant="h5" gutterBottom>
        Blob Viewer
      </Typography>
      <Box marginBottom={2} display="flex" justifyContent="space-between">
        <Box display="flex" gap={2}>
          <BlobUploader onUploadSuccess={handleUploadSuccess} />
          <Button variant="contained" color="secondary" onClick={fetchBlobsFromAllContainers} disabled={refreshLoading}>
            {refreshLoading ? 'Refreshing...' : 'Refresh'}
          </Button>
          
        </Box>
        <DeleteButton
          selectedBlobs={selectedBlobs}
          deleteLoading={deleteLoading}
          onDeleteConfirm={handleDeleteConfirm}
        />
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
