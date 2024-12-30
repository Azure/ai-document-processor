// PromptEditor.tsx
import React, { useEffect, useState } from 'react';
import { Box, Typography, TextField, Button } from '@mui/material';

// Define the shape of your prompts data
interface PromptsData {
  prompt1: string;
  prompt2: string;
  // add more if needed
}

const PromptEditor: React.FC = () => {
  const [prompts, setPrompts] = useState<PromptsData>({
    prompt1: '',
    prompt2: '',
  });
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  const fetchPrompts = async () => {
    setLoading(true);
    setMessage(null);

    try {
      const response = await fetch('http://localhost:5000/api/prompts'); 
      // Adjust port/URL to your backend
      if (!response.ok) {
        throw new Error(`Error fetching prompts: ${response.statusText}`);
      }
      const data: PromptsData = await response.json();
      setPrompts(data);
    } catch (error: any) {
      console.error(error);
      setMessage(error.message);
    } finally {
      setLoading(false);
    }
  };

  const updatePrompts = async () => {
    setLoading(true);
    setMessage(null);

    try {
      const response = await fetch('http://localhost:5000/api/prompts', {
        method: 'POST', 
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(prompts),
      });
      if (!response.ok) {
        throw new Error(`Error updating prompts: ${response.statusText}`);
      }
      const data = await response.json();
      setMessage(data.message);
    } catch (error: any) {
      console.error(error);
      setMessage(error.message);
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    // Fetch the prompts when the component mounts
    fetchPrompts();
  }, []);

  // Handle changes to the text fields
  const handlePromptChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const { name, value } = e.target;
    setPrompts((prev) => ({ ...prev, [name]: value }));
  };

  return (
    <Box sx={{ border: '1px solid #ccc', p: 2, borderRadius: 1 }}>
      <Typography variant="h6" gutterBottom>
        Edit Prompts
      </Typography>

      {message && <Typography color="error">{message}</Typography>}

      {loading && <Typography>Loading...</Typography>}

      {!loading && (
        <>
          <TextField
            label="Prompt 1"
            name="prompt1"
            value={prompts.prompt1}
            onChange={handlePromptChange}
            fullWidth
            multiline
            rows={3}
            margin="normal"
          />
          <TextField
            label="Prompt 2"
            name="prompt2"
            value={prompts.prompt2}
            onChange={handlePromptChange}
            fullWidth
            multiline
            rows={3}
            margin="normal"
          />

          <Button
            variant="contained"
            color="primary"
            onClick={updatePrompts}
            disabled={loading}
            sx={{ mt: 2 }}
          >
            Save Prompts
          </Button>
        </>
      )}
    </Box>
  );
};

export default PromptEditor;
