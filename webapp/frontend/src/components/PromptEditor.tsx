import React, { useEffect, useState } from 'react';
import { Box, Button, Typography, Grid, Card, CardContent } from '@mui/material';
interface Prompts {
  [key: string]: string; // Allows dynamic key-value pairs
}

const functionUrl = `/api/getPrompts`;

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
      if (!functionUrl) {
        throw new Error('Function URL is not set');
      }
      
      const response = await fetch(functionUrl);
      if (!response.ok) {
        throw new Error(`Error fetching prompts: ${response.statusText}`);
      }

      const data: Prompts = await response.json();
      setPrompts(data);
    } catch (error: unknown) {
      if (error instanceof Error) {
        setErrorMessage(error.message || "Unknown error occurred");
      }
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
          <Grid container spacing={2}>
          {Object.entries(prompts).map(([key, value]) => (
            <Grid item xs={12} sm={6} md={4} key={key}>
              <Card variant="outlined">
                <CardContent>
                  <Typography variant="subtitle1" fontWeight="bold">{key}</Typography>
                  <Typography variant="body2">{value}</Typography>
                </CardContent>
              </Card>
            </Grid>
          ))}
        </Grid>
      )}

      {!loading && !errorMessage && Object.keys(prompts).length === 0 && (
        <Typography>No prompts available</Typography>
      )}
    </div>
  );
};

export default PromptEditor;