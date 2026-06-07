export type RitmState = 'Pending Validation' | 'Pending Approval' | 'On Hold' | 'Approved' | 'In Progress' | 'Closed Complete' | 'Closed Incomplete' | 'Closed Skipped' | 'Cancelled';

export interface RequestItem {
  id: number;
  ritmNumber: string;
  parentTicketId: number;
  catalogItemId: number;
  catalogItem?: string;
  requestedFor: string;
  ritmState: RitmState;
  variables?: string;
  created?: string;
  modified?: string;
  // Populated for the Service Desk hand-off queue
  workNotes?: string;
  assignmentGroup?: string;
}
