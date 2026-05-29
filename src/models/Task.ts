export type TaskState = 'Open' | 'In Progress' | 'On Hold' | 'Closed Complete' | 'Closed Incomplete' | 'Closed Skipped' | 'Cancelled';

export interface Task {
  id: number;
  taskNumber: string;
  parentRitmId: number;
  taskState: TaskState;
  shortDescription: string;
  jobType?: string;
  linkedJobId?: string;
  sortOrder?: number;
}
