// frontend/src/components/DeleteButton.tsx
import React, { useState } from 'react';
import { 
  Button, 
  Dialog, 
  DialogTitle, 
  DialogContent, 
  DialogActions, 
  Typography 
} from '@mui/material';
import { BlobItem } from './BlobList';  // Import the BlobItem type

interface DeleteButtonProps {
  selectedBlobs: BlobItem[];
  deleteLoading: boolean;
  onDeleteConfirm: () => void;  // Changed from onDeleteClick to onDeleteConfirm
}

const DeleteButton: React.FC<DeleteButtonProps> = ({
  selectedBlobs,
  deleteLoading,
  onDeleteConfirm
}) => {
  const [confirmDialogOpen, setConfirmDialogOpen] = useState(false);

  const handleDeleteClick = () => {
    if (selectedBlobs.length === 0) return;
    setConfirmDialogOpen(true);
  };

  const handleCloseDialog = () => {
    setConfirmDialogOpen(false);
  };

  const handleConfirmDelete = () => {
    setConfirmDialogOpen(false);
    onDeleteConfirm();
  };

  return (
    <>
      <Button 
        variant="contained" 
        color="error" 
        onClick={handleDeleteClick} 
        disabled={selectedBlobs.length === 0 || deleteLoading}
      >
        {deleteLoading ? 'Deleting...' : `Delete Selected (${selectedBlobs.length})`}
      </Button>

      <Dialog
        open={confirmDialogOpen}
        onClose={handleCloseDialog}
      >
        <DialogTitle>Confirm Deletion</DialogTitle>
        <DialogContent>
          <Typography>
            Are you sure you want to delete {selectedBlobs.length} selected blob(s)? This action cannot be undone.
          </Typography>
        </DialogContent>
        <DialogActions>
          <Button onClick={handleCloseDialog}>Cancel</Button>
          <Button onClick={handleConfirmDelete} color="error" autoFocus>
            Delete
          </Button>
        </DialogActions>
      </Dialog>
    </>
  );
};

export default DeleteButton;