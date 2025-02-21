import React, { useEffect, useState } from 'react';
import {
  Container,
  Grid,
  Card,
  CardContent,
  CardActions,
  Typography,
  Button,
  Box,
  Dialog,
  DialogTitle,
  DialogContent,
  DialogActions,
  TextField
} from '@mui/material';
import { v4 as uuidv4 } from 'uuid';

export interface Prompt {
  id: string;
  name: string;
  system_prompt: string;
  user_prompt: string;
}

const PromptEditor: React.FC = () => {
  const [prompts, setPrompts] = useState<Prompt[]>([]);
  const [livePromptId, setLivePromptId] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  // States for update dialog
  const [updateDialogOpen, setUpdateDialogOpen] = useState(false);
  const [selectedPrompt, setSelectedPrompt] = useState<Prompt | null>(null);
  const [editedSystemPrompt, setEditedSystemPrompt] = useState('');
  const [editedUserPrompt, setEditedUserPrompt] = useState('');

  // States for create dialog
  const [createDialogOpen, setCreateDialogOpen] = useState(false);
  const [newPromptName, setNewPromptName] = useState('');
  const [newSystemPrompt, setNewSystemPrompt] = useState('');
  const [newUserPrompt, setNewUserPrompt] = useState('');

  // Fetch prompts from the backend
  const fetchPrompts = async () => {
    setLoading(true);
    setError(null);
    try {
      const response = await fetch('/api/list_prompts');
      if (!response.ok) {
        throw new Error(`Error: ${response.status}`);
      }
      const data = await response.json();
      setPrompts(data.prompts);
      setLivePromptId(data.livePromptId);
    } catch {
      setError('Error deleting prompt');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    fetchPrompts();
  }, []);

  const handleDelete = async (id: string) => {
    try {
      const res = await fetch(`/api/delete_prompt?id=${id}`, { method: 'DELETE' });
      if (res.ok) {
        setPrompts((prev) => prev.filter((p) => p.id !== id));
      } else {
        setError('Error deleting prompt');
      }
    } catch {
      setError('Error deleting prompt');
    }
  };

  const handleSelect = async (id: string) => {
    try {
      const res = await fetch('/api/select_live_prompt', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ id }),
      });
      if (res.ok) {
        setLivePromptId(id);
      } else {
        setError('Error selecting live prompt');
      }
    } catch (err) {
      setError('Error selecting live prompt');
    }
  };

  const openUpdateDialog = (prompt: Prompt) => {
    setSelectedPrompt(prompt);
    setEditedSystemPrompt(prompt.system_prompt);
    setEditedUserPrompt(prompt.user_prompt);
    setUpdateDialogOpen(true);
  };

  const handleUpdate = async () => {
    if (!selectedPrompt) return;
    const updatedPrompt = {
      ...selectedPrompt,
      system_prompt: editedSystemPrompt,
      user_prompt: editedUserPrompt,
    };
    try {
      const res = await fetch('/api/update_prompt', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(updatedPrompt),
      });
      const data = await res.json();
      setPrompts((prev) => prev.map((p) => (p.id === data.id ? data : p)));
      setUpdateDialogOpen(false);
    } catch (err) {
      setError('Error updating prompt');
    }
  };

  // Handle Create Prompt submission
  const handleCreatePromptSubmit = async () => {
    const generatedId = uuidv4();
    console.log('Generated ID:', generatedId);

    const newPrompt = {
      name: newPromptName,
      system_prompt: newSystemPrompt,
      user_prompt: newUserPrompt
    };
    
    try {
      const res = await fetch('/api/create_prompt', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(newPrompt),
      });
      const data = await res.json();
      setPrompts((prev) => [...prev, data]);
      setCreateDialogOpen(false);
      // Reset form fields
      setNewPromptName('');
      setNewSystemPrompt('');
      setNewUserPrompt('');
    } catch (err) {
      setError('Error creating prompt');
    }
  };

  const livePrompt = prompts.find((p) => p.id === livePromptId);
  const alternatePrompts = prompts.filter((p) => p.id !== livePromptId);

  return (
    <Container maxWidth="md" sx={{ mt: 4, p: 2, border: '1px solid #ddd', borderRadius: '4px' }}>
      <Typography variant="h5" gutterBottom align="center">
        Prompt Editor
      </Typography>

      {/* Refresh button at the top, centered */}
      <Box display="flex" justifyContent="center" mb={2}>
        <Button variant="contained" color="secondary" onClick={fetchPrompts} disabled={loading}>
          {loading ? 'Refreshing...' : 'Refresh'}
        </Button>
      </Box>

      {error && (
        <Typography variant="body1" color="error" gutterBottom align="center">
          {error}
        </Typography>
      )}

      {/* Live Prompt Section */}
      <Box mb={4}>
        <Typography variant="h6" gutterBottom>
          Live Prompt
        </Typography>
        {livePrompt ? (
          <Card variant="outlined" sx={{ p: 2 }}>
            <CardContent>
              <Grid container spacing={2}>
                <Grid item xs={6}>
                  <Typography variant="subtitle2" color="textSecondary">
                    System Prompt
                  </Typography>
                  <Typography variant="body1">
                    {livePrompt.system_prompt}
                  </Typography>
                </Grid>
                <Grid item xs={6}>
                  <Typography variant="subtitle2" color="textSecondary">
                    User Prompt
                  </Typography>
                  <Typography variant="body1">
                    {livePrompt.user_prompt}
                  </Typography>
                </Grid>
              </Grid>
            </CardContent>
          </Card>
        ) : (
          <Typography variant="body2">No live prompt selected.</Typography>
        )}
      </Box>

      {/* Alternate Prompts as Tiles */}
      <Box mb={4}>
        <Typography variant="h6" gutterBottom>
          Alternate Prompts
        </Typography>
        <Grid container spacing={2}>
          {alternatePrompts.map((prompt) => (
            <Grid item xs={12} sm={6} md={4} key={prompt.id}>
              <Card variant="outlined" sx={{ height: '100%' }}>
                <CardContent>
                  <Typography variant="subtitle2" color="textSecondary">
                    {prompt.name}
                  </Typography>
                  <Box mt={1}>
                    <Typography variant="subtitle2" color="textSecondary">
                      System Prompt
                    </Typography>
                    <Typography variant="body2">
                      {prompt.system_prompt}
                    </Typography>
                  </Box>
                  <Box mt={1}>
                    <Typography variant="subtitle2" color="textSecondary">
                      User Prompt
                    </Typography>
                    <Typography variant="body2">
                      {prompt.user_prompt}
                    </Typography>
                  </Box>
                </CardContent>
                <CardActions sx={{ justifyContent: 'center' }}>
                  <Button
                    size="small"
                    variant="contained"
                    color="primary"
                    onClick={() => handleSelect(prompt.id)}
                  >
                    Select as Live
                  </Button>
                  <Button
                    size="small"
                    variant="outlined"
                    color="secondary"
                    onClick={() => openUpdateDialog(prompt)}
                  >
                    Update
                  </Button>
                  <Button
                    size="small"
                    variant="text"
                    color="error"
                    onClick={() => handleDelete(prompt.id)}
                  >
                    Delete
                  </Button>
                </CardActions>
              </Card>
            </Grid>
          ))}
        </Grid>
      </Box>

      {/* Create New Prompt button at the bottom, centered */}
      <Box display="flex" justifyContent="center" mt={4}>
      <Button 
        variant="contained" 
        color="primary" 
        onClick={() => {
          console.log('Create New Prompt button clicked');
          setCreateDialogOpen(true);
        }}
      >
        Create New Prompt
      </Button>

      </Box>

      {/* Update Dialog */}
      <Dialog
        open={updateDialogOpen}
        onClose={() => setUpdateDialogOpen(false)}
        fullWidth
        maxWidth="sm"
      >
        <DialogTitle>Update Prompt</DialogTitle>
        <DialogContent>
          <TextField
            margin="dense"
            label="System Prompt"
            fullWidth
            multiline
            value={editedSystemPrompt}
            onChange={(e) => setEditedSystemPrompt(e.target.value)}
          />
          <TextField
            margin="dense"
            label="User Prompt"
            fullWidth
            multiline
            value={editedUserPrompt}
            onChange={(e) => setEditedUserPrompt(e.target.value)}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setUpdateDialogOpen(false)}>Cancel</Button>
          <Button onClick={handleUpdate} variant="contained" color="primary">
            Save
          </Button>
        </DialogActions>
      </Dialog>

      {/* Create Prompt Dialog */}
      <Dialog
        open={createDialogOpen}
        onClose={() => setCreateDialogOpen(false)}
        fullWidth
        maxWidth="sm"
      >
        <DialogTitle>Create New Prompt</DialogTitle>
        <DialogContent>
          <TextField
            margin="dense"
            label="Prompt Name"
            fullWidth
            value={newPromptName}
            onChange={(e) => setNewPromptName(e.target.value)}
          />
          <TextField
            margin="dense"
            label="System Prompt"
            fullWidth
            multiline
            value={newSystemPrompt}
            onChange={(e) => setNewSystemPrompt(e.target.value)}
          />
          <TextField
            margin="dense"
            label="User Prompt"
            fullWidth
            multiline
            value={newUserPrompt}
            onChange={(e) => setNewUserPrompt(e.target.value)}
          />
        </DialogContent>
        <DialogActions>
          <Button onClick={() => setCreateDialogOpen(false)}>Cancel</Button>
          <Button onClick={handleCreatePromptSubmit} variant="contained" color="primary">
            Create
          </Button>
        </DialogActions>
      </Dialog>
    </Container>
  );
};

export default PromptEditor;
