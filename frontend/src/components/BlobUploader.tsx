import React, { useState, useRef } from 'react';
import { 
  Button, Dialog, DialogTitle, DialogContent, DialogActions, 
  Box, FormControl, InputLabel, Select, MenuItem, Alert
} from '@mui/material';
import { SelectChangeEvent } from '@mui/material/Select';

const CONTAINER_NAMES = ['bronze', 'silver', 'gold'];
const uploadBlobUrl = `/api/uploadBlob`;

interface BlobUploaderProps {
  onUploadSuccess: () => void;
}

const BlobUploader: React.FC<BlobUploaderProps> = ({ onUploadSuccess }) => {
  const [open, setOpen] = useState(false);
  const [container, setContainer] = useState('bronze');
  const [file, setFile] = useState<File | null>(null);
  const [status, setStatus] = useState<{ loading: boolean; error?: string; success?: string }>({ loading: false });
  const fileInputRef = useRef<HTMLInputElement>(null);

  const handleOpen = () => setOpen(true);
  const handleClose = () => setOpen(false);

  const handleContainerChange = (event: SelectChangeEvent) => {
    setContainer(event.target.value);
  };

  const handleFileChange = (event: React.ChangeEvent<HTMLInputElement>) => {
    if (event.target.files && event.target.files.length > 0) {
      setFile(event.target.files[0]);
    }
  };

  const handleUpload = async () => {
    if (!file) return;

    setStatus({ loading: true });

    try {
      // Read file as base64
      const reader = new FileReader();
      reader.readAsDataURL(file);
      
      reader.onload = async () => {
        try {
          const base64Content = (reader.result as string).split(',')[1];
          
          const response = await fetch(uploadBlobUrl, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({
              container: container,
              filename: file.name,
              fileContent: base64Content,
            }),
          });

          if (!response.ok) {
            throw new Error('Upload failed');
          }

          // Success
          setStatus({ loading: false, success: 'Upload successful' });
          onUploadSuccess();
          
          // Reset and close
          setTimeout(() => {
            setOpen(false);
            setFile(null);
            if (fileInputRef.current) fileInputRef.current.value = '';
          }, 1500);
          
        } catch (err) {
          setStatus({ loading: false, error: 'Upload failed' });
        }
      };

      reader.onerror = () => {
        setStatus({ loading: false, error: 'Could not read file' });
      };

    } catch (err) {
      setStatus({ loading: false, error: 'Upload failed' });
    }
  };

  return (
    <>
      <Button variant="contained" onClick={handleOpen}>Upload</Button>

      <Dialog open={open} onClose={handleClose} maxWidth="sm" fullWidth>
        <DialogTitle>Upload File</DialogTitle>
        <DialogContent>
          <Box sx={{ mt: 2, mb: 2 }}>
            {status.error && <Alert severity="error" sx={{ mb: 2 }}>{status.error}</Alert>}
            {status.success && <Alert severity="success" sx={{ mb: 2 }}>{status.success}</Alert>}
            
            <FormControl fullWidth sx={{ mb: 2 }}>
              <InputLabel>Container</InputLabel>
              <Select
                value={container}
                label="Container"
                onChange={handleContainerChange}
                disabled={status.loading}
              >
                {CONTAINER_NAMES.map((name) => (
                  <MenuItem key={name} value={name}>{name}</MenuItem>
                ))}
              </Select>
            </FormControl>
            
            <input
              type="file"
              onChange={handleFileChange}
              ref={fileInputRef}
              disabled={status.loading}
            />
          </Box>
        </DialogContent>
        <DialogActions>
          <Button onClick={handleClose} disabled={status.loading}>Cancel</Button>
          <Button 
            onClick={handleUpload} 
            variant="contained" 
            disabled={!file || status.loading}
          >
            {status.loading ? 'Uploading...' : 'Upload'}
          </Button>
        </DialogActions>
      </Dialog>
    </>
  );
};

export default BlobUploader; 