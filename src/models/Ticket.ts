export type TicketType = 'Incident' | 'Request' | 'Change' | 'Problem';
export type TicketState = 'New' | 'In Progress' | 'On Hold' | 'Resolved' | 'Closed' | 'Cancelled';
export type SlaStatus = 'Not Started' | 'On Track' | 'Warning' | 'Breached' | 'Met';

export interface Ticket {
  id: number;
  title: string;
  ticketType: TicketType;
  ticketState: TicketState;
  shortDescription: string;
  description?: string;
  category?: string;
  subcategory?: string;
  caller?: string;
  priority?: string;
  impact?: string;
  urgency?: string;
  closeCode?: string;
  closeNotes?: string;
  closedDate?: string;
  workNotes?: string;
  ticketSource?: string;
  confidentialityLevel?: string;
  ticketTypeValidated?: boolean;
  ticketTypeValidationStatus?: string;
  ticketTypeValidationReason?: string;
  suggestedTicketType?: TicketType;
  typeOverrideConfirmed?: boolean;
  escalationFlag?: boolean;
  ticketFollowerIds?: number[];
  slaStatus?: SlaStatus;
  slaPercentElapsed?: number;
  created?: string;
  modified?: string;
}
