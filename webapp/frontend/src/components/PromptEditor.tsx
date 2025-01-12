import React, { useEffect, useState } from 'react';
import { Box, Button, Typography } from '@mui/material';
import { BlobServiceClient } from '@azure/storage-blob';

// Shape of your prompts file (adjust to match your JSON structure)
interface Prompts {
  prompt1: string;
  prompt2: string;
}

const containerName = 'prompts';      // Adjust as needed
const blobName = 'prompts.json';      // The blob storing your prompts

const PromptEditor: React.FC = () => {
  const [prompts, setPrompts] = useState<Prompts>({ prompt1: '', prompt2: '' });
  const [loading, setLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  // Fetch prompts from the blob when component mounts
  useEffect(() => {
    fetchPromptsFromBlob();
  }, []);

  // Download the prompts blob and parse the JSON
  const fetchPromptsFromBlob = async () => {
    setLoading(true);
    setErrorMessage(null);

    try {
      const blobServiceClient = new BlobServiceClient(
        ''
      );
      const containerClient = blobServiceClient.getContainerClient(containerName);
      const blobClient = containerClient.getBlobClient(blobName);

      // Download the blob
      const downloadResponse = await blobClient.download();
      const blobData = await downloadResponse.blobBody;
      const textData = await blobData?.text();
      if (textData) {
        const parsedPrompts = JSON.parse(textData);
        setPrompts(parsedPrompts);
      }
    } catch (error: any) {
      setErrorMessage(`Error fetching prompts: ${error.message}`);
    } finally {
      setLoading(false);
    }
  };

  const handleRefresh = () => {
    fetchPromptsFromBlob();
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

      {!loading && !errorMessage && (
        <>
          <Typography variant="body1">
            <strong>Prompt 1:</strong> {prompts.prompt1}
          </Typography>
          <Typography variant="body1">
            <strong>Prompt 2:</strong> {prompts.prompt2}
          </Typography>
        </>
      )}
    </div>
  );
};

export default PromptEditor;
