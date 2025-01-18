import React, { useEffect, useState } from 'react';
import { Box, Button, Typography } from '@mui/material';

interface Prompts {
  [key: string]: string; // Allows dynamic key-value pairs
}
const functionUrl = ""

// const functionUrl = "https://<your-function-app>.azurewebsites.net/api/getPrompts"; // Replace with your function URL

const PromptEditor: React.FC = () => {
  const [prompts, setPrompts] = useState<Prompts>({});
  const [loading, setLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Fetch prompts from the Azure Function
  useEffect(() => {
    fetchPrompts();
  }, []);

  const fetchPrompts = async () => {
    setLoading(true);
    setErrorMessage(null);

    try {
      const blobServiceClient = new BlobServiceClient(
        ''
      );
      const containerClient = blobServiceClient.getContainerClient(containerName);
      const blobClient = containerClient.getBlobClient(blobName);
      const response = await fetch(functionUrl);

      if (!response.ok) {
        throw new Error(`Error fetching prompts: ${response.statusText}`);
      }

      const data: Prompts = await response.json();
      setPrompts(data);
    } catch (error: any) {
      setErrorMessage(error.message || "Unknown error occurred");
    } finally {
      setLoading(false);
    }
  };

  const handleRefresh = () => {
    fetchPrompts();
  };

  return (
    <div style={{ padding: '1rem', border: '1px solid #ddd', borderRadius: '4px' }}>
      <Typography variant="h5" gutterBottom>
        Prompt Viewer
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

      {loading && <Typography>Loading...</Typography>}
      {errorMessage && <Typography color="error">{errorMessage}</Typography>}

      {!loading && !errorMessage && Object.keys(prompts).length > 0 && (
        <Box>
          {Object.entries(prompts).map(([key, value]) => (
            <Typography key={key} variant="body1">
              <strong>{key}:</strong> {value}
            </Typography>
          ))}
        </Box>
      )}

      {!loading && !errorMessage && Object.keys(prompts).length === 0 && (
        <Typography>No prompts available</Typography>
      )}
    </div>
  );
};

export default PromptEditor;