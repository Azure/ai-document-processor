// import React from 'react';
import { Container, Typography, Button, Box, Grid } from '@mui/material';
import BlobList from './components/BlobList';
import PromptEditor from './components/PromptEditor';

function App() {
  // Replace this URL with your actual Azure Function endpoint
  const azureFunctionUrl = '/api/processUploads'; 

  const callAzureFunction = async () => {
    try {
      const response = await fetch(azureFunctionUrl, {
        method: 'POST', // or 'POST', depending on your function
      });
      if (!response.ok) {
        throw new Error(`Error calling Azure Function: ${response.statusText}`);
      }
      const data = await response.json();
      console.log('Azure Function response:', data);
      alert(`Azure Function called successfully! Response: ${JSON.stringify(data)}`);
    } catch (error) {
      console.error('Error calling Azure Function:', error);
      alert(`Error: ${error}`);
    }
  };

  return (
    <Container maxWidth={false} disableGutters sx={{ textAlign: 'center', py: 4 }}>
      <Typography variant="h4" gutterBottom>
        Digital Reporting Assistant
      </Typography>

      <Box marginY={2}>
        <Button variant="contained" color="primary" onClick={callAzureFunction}>
          Call Azure Function
        </Button>
      </Box>

      {/* Two-column layout */}
      <Grid container spacing={2}>
        {/* Left column: Blob viewer */}
        <Grid item xs={12} md={6} >
          <BlobList />
        </Grid>

        {/* Right column: Prompt Editor */}
        <Grid item xs={12} md={6} >
          <PromptEditor />
        </Grid>
      </Grid>

    </Container>
  );
}

export default App;
