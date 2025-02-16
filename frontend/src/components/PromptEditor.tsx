import React, { useEffect, useState } from 'react';
import {
  Box,
  Button,
  Typography,
  Grid,
  Card,
  CardContent,
  TextField,
  IconButton,
} from '@mui/material';
import { Delete, Edit } from '@mui/icons-material';

interface Prompt {
  id: string;
  name: string;
  promptvalue: string;
}

const functionBaseUrl = '/data-api/graphql'; // Azure SWA Data API for Cosmos DB

const PromptEditor: React.FC = () => {
  const [prompts, setPrompts] = useState<Prompt[]>([]);
  const [newPrompt, setNewPrompt] = useState({ name: '', promptvalue: '' });
  const [editingPrompt, setEditingPrompt] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  useEffect(() => {
    fetchPrompts();
  }, []);

  // Fetch prompts from the CosmosDB Data API
  const fetchPrompts = async () => {
    setLoading(true);
    setErrorMessage(null);
    try {
      const query = {
        query: `
        {
          prompts {
            items {
              id
              name
              promptvalue
            }
          }
        }`,
      };

      const response = await fetch(functionBaseUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(query),
      });
      

      if (!response.ok) {
        throw new Error(`Error fetching prompts: ${response.statusText}`);
      }

      const data = await response.json();
      console.log(data.data.prompts.items)
      setPrompts(data.data.prompts.items);
    } catch (error) {
      if (error instanceof Error) {
        setErrorMessage(error.message || 'Unknown error occurred');
      }
    } finally {
      setLoading(false);
    }
  };

  // Create a new prompt
  const createPrompt = async () => {
    if (!newPrompt.name || !newPrompt.promptvalue) {
      setErrorMessage('Name and Value are required');
      return;
    }
    setErrorMessage(null);

    try {
      const query = {
        query: `
        mutation create($item: CreatePromptInput!) {
          createPrompt(item: $item) {
            id
            name
            promptvalue
          }
        }`,
        variables: { item: { id: Date.now().toString(), ...newPrompt } },
      };

      const response = await fetch(functionBaseUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(query),
      });

      if (!response.ok) throw new Error('Failed to create prompt');

      await fetchPrompts();
      setNewPrompt({ name: '', promptvalue: '' });
    } catch (error) {
      setErrorMessage('Failed to create prompt');
    }
  };

  // Edit an existing prompt
  const editPrompt = async (id: string, updatedValue: string) => {
    try {
      const query = {
        query: `
        mutation update($id: ID!, $item: UpdatePromptInput!) {
          updatePrompt(id: $id, _partitionKeyValue: $id, item: $item) {
            id
            name
            promptvalue
          }
        }`,
        variables: { id, item: { promptvalue: updatedValue } },
      };

      const response = await fetch(functionBaseUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(query),
      });

      if (!response.ok) throw new Error('Failed to update prompt');

      setEditingPrompt(null);
      await fetchPrompts();
    } catch (error) {
      setErrorMessage('Failed to update prompt');
    }
  };

  // Delete a prompt
  const deletePrompt = async (id: string) => {
    try {
      const query = {
        query: `
        mutation delete($id: ID!, $_partitionKeyValue: String!) {
          deletePrompt(id: $id, _partitionKeyValue: $_partitionKeyValue) {
            id
          }
        }`,
        variables: { id, _partitionKeyValue: id },
      };

      const response = await fetch(functionBaseUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(query),
      });

      if (!response.ok) throw new Error('Failed to delete prompt');

      await fetchPrompts();
    } catch (error) {
      setErrorMessage('Failed to delete prompt');
    }
  };

  return (
    <div style={{ padding: '1rem', border: '1px solid #ddd', borderRadius: '4px' }}>
      <Typography variant="h5" gutterBottom>
        Prompt Manager
      </Typography>

      <Box marginBottom={2}>
        <Button variant="contained" color="secondary" onClick={fetchPrompts} disabled={loading}>
          {loading ? 'Refreshing...' : 'Refresh'}
        </Button>
      </Box>

      {loading && <Typography>Loading...</Typography>}
      {errorMessage && <Typography color="error">{errorMessage}</Typography>}

      {/* New Prompt Form */}
      <Box display="flex" flexDirection="column" gap={2} marginBottom={2}>
        <TextField
          label="Prompt Name"
          variant="outlined"
          value={newPrompt.name}
          onChange={(e) => setNewPrompt({ ...newPrompt, name: e.target.value })}
        />
        <TextField
          label="Prompt Value"
          variant="outlined"
          value={newPrompt.promptvalue}
          onChange={(e) => setNewPrompt({ ...newPrompt, promptvalue: e.target.value })}
        />
        <Button variant="contained" color="primary" onClick={createPrompt}>
          Add Prompt
        </Button>
      </Box>

      {/* Prompt List */}
      {!loading && !errorMessage && prompts.length > 0 && (
        <Grid container spacing={2}>
          {prompts.map((prompt) => (
            <Grid item xs={12} sm={6} md={4} key={prompt.id}>
              <Card variant="outlined">
                <CardContent>
                  <Typography variant="subtitle1" fontWeight="bold">{prompt.name}</Typography>

                  {editingPrompt === prompt.id ? (
                    <TextField
                      fullWidth
                      variant="outlined"
                      defaultValue={prompt.promptvalue}
                      onBlur={(e) => editPrompt(prompt.id, e.target.value)}
                      autoFocus
                    />
                  ) : (
                    <Typography variant="body2">{prompt.promptvalue}</Typography>
                  )}

                  <Box display="flex" justifyContent="space-between" marginTop={2}>
                    <IconButton color="primary" onClick={() => setEditingPrompt(prompt.id)}>
                      <Edit />
                    </IconButton>
                    <IconButton color="error" onClick={() => deletePrompt(prompt.id)}>
                      <Delete />
                    </IconButton>
                  </Box>
                </CardContent>
              </Card>
            </Grid>
          ))}
        </Grid>
      )}

      {!loading && !errorMessage && prompts.length === 0 && <Typography>No prompts available</Typography>}
    </div>
  );
};

export default PromptEditor;
