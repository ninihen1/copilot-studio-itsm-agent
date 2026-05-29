export type ProvisioningJobStatus = 'Proposed' | 'AwaitingApproval' | 'Rejected' | 'DispatchRejected' | 'DispatchFailed' | 'Dispatched' | 'Queued' | 'InProgress' | 'Succeeded' | 'Failed' | 'Compensated' | 'DeadLettered' | 'Cancelled';

export interface ProvisioningJob {
  id: number;
  jobId: string;
  jobType: string;
  parentTicketId: number;
  parentRitmId?: number;
  jobStatus: ProvisioningJobStatus;
  callerUpn: string;
  targetJson: string;
  argsJson?: string;
  correlationId: string;
  servicePrincipal?: string;
  graphRequestId?: string;
  errorJson?: string;
  retryCount?: number;
  created?: string;
  modified?: string;
}
