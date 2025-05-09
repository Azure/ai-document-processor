import { Container, Typography, Button, Box, Grid } from '@mui/material';
import BlobList, { BlobItem } from './components/BlobList';
import PromptEditor from './components/PromptEditor';
import { useState } from 'react';

function App() {
  const [selectedBlobs, setSelectedBlobs] = useState<BlobItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState('');

  // Azure Function URLs
  const azureFunctionUrls = {
    startWorkflow: '/api/startWorkflow',
  };

  // Generic function to call Azure Functions
  const callAzureFunction = async (url: string, requiredContainer: string) => {
    const validBlobs = selectedBlobs.filter(blob => blob.container === requiredContainer);
    if (validBlobs.length === 0) {
      alert(`Please select a file in the ${requiredContainer} container for this function to process`);
      return;
    }

    if (selectedBlobs.some(blob => blob.container !== requiredContainer)) {
      alert(`Please select only files in the ${requiredContainer} container for this function to process`);
      return;
    }
    
    setLoading(true);
    setMessage('Launching job...');
    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ blobs: selectedBlobs })
      });

      const data = await response.json(); // Directly parse as JSON

      if (!response.ok) {
        console.error('Azure Function response:', data);
        setMessage(`Error: ${data.errors?.join('\n') || 'Unknown error'}`);
      } else {
        console.log('Azure Function response:', data);
        setMessage('Azure started the job successfully!');

        // Polling for job status
        const statusUri = data.statusQueryGetUri;
        let jobCompleted = false;

        while (!jobCompleted) {
          const statusResponse = await fetch(statusUri);
          const statusData = await statusResponse.json();

          if (statusResponse.ok) {
            console.log('Job Status:', statusData);
            setMessage(`Job Status: ${statusData.runtimeStatus}`);

            if (statusData.runtimeStatus === 'Completed' || statusData.runtimeStatus === 'Failed' || statusData.runtimeStatus === 'Terminated') {
              jobCompleted = true;

              const results = statusData.output;
              const failedTasks = results.filter((result: any) => !result.task_result.success);

              if (failedTasks.length > 0) {
                setMessage(`Job Failed. ${failedTasks.length} tasks failed.`);
              } else {
                setMessage(`Job Completed.`);
              }
            }
          } else {
            console.error('Error fetching job status:', statusData);
            setMessage(`Error fetching job status: ${statusData.errors?.join('\n') || 'Unknown error'}`);
            jobCompleted = true;
          }

          // Wait for a few seconds before polling again
          await new Promise(resolve => setTimeout(resolve, 5000));
        }
      }
    } catch (error) {
      console.error('Error calling Azure Function:', error);
      setMessage(`Error: ${error}`);
    } finally {
      setLoading(false);
    }
  };

  return (
    <Container maxWidth={false} disableGutters sx={{ textAlign: 'center', py: 0 }}>
      <Box
        sx={{
          backgroundColor: '#0A1F44',
          color: 'white',
          py: 3,
          px: 2,
          textAlign: 'center',
          boxShadow: 3,
        }}
      >
        <Typography variant="h4" gutterBottom>
          AI Document Processor
        </Typography>

        {/* Two buttons at the top */}
        <Box display="flex" justifyContent="center" gap={2} marginTop={2}>
          <Button 
            variant="contained" 
            color="primary" 
            onClick={() => callAzureFunction(azureFunctionUrls.startWorkflow, "bronze")}
            disabled={loading}
          >
            {loading ? 'Processing...' : 'Start Workflow'}
          </Button>

        </Box>
        {message && <Typography variant="body1" color="secondary">{message}</Typography>}
      </Box>

      {/* Two-column layout */}
      <Grid container spacing={2} alignItems="stretch">
        {/* Left column: Blob viewer */}
        <Grid item xs={12} md={6} sx= {{ display: 'flex' }}>
          <BlobList onSelectionChange={setSelectedBlobs} />
        </Grid>

        {/* Right column: Prompt Editor */}
        <Grid item xs={12} md={6}>
          <PromptEditor />
        </Grid>
      </Grid>
    </Container>
  );
}

export default App;
