import { ProvisioningJob } from '../models/ProvisioningJob';
import { ISharePointServiceContext, SharePointServiceBase } from './SharePointServiceBase';

interface IListResponse<T> {
  value: T[];
}

interface IProvisioningJobListItem {
  Id: number;
  Title: string;
  JobType?: string;
  ParentTicketId?: number;
  ParentRitmId?: number;
  JobStatus?: ProvisioningJob['jobStatus'];
  CallerUpn?: string;
  TargetJson?: string;
  ArgsJson?: string;
  CorrelationId?: string;
  ServicePrincipal?: string;
  GraphRequestId?: string;
  ErrorJson?: string;
  RetryCount?: number;
  Created?: string;
  Modified?: string;
}

export class JobAuditService extends SharePointServiceBase {
  public constructor(context: ISharePointServiceContext) {
    super(context);
  }

  public async getJobsForTicket(ticketId: number): Promise<ProvisioningJob[]> {
    const response = await this.get<IListResponse<IProvisioningJobListItem>>(this.listItemsUrl('Provisioning Jobs', `?$select=Id,Title,JobType,ParentTicketId,ParentRitmId,JobStatus,CallerUpn,TargetJson,ArgsJson,CorrelationId,ServicePrincipal,GraphRequestId,ErrorJson,RetryCount,Created,Modified&$filter=ParentTicketId eq ${ticketId}&$orderby=Created desc&$top=50`));
    return response.value.map(item => this.mapJob(item));
  }

  public async getFailedJobs(): Promise<ProvisioningJob[]> {
    const response = await this.get<IListResponse<IProvisioningJobListItem>>(this.listItemsUrl('Provisioning Jobs', "?$select=Id,Title,JobType,ParentTicketId,ParentRitmId,JobStatus,CallerUpn,TargetJson,ArgsJson,CorrelationId,ServicePrincipal,GraphRequestId,ErrorJson,RetryCount,Created,Modified&$filter=JobStatus eq 'Failed'&$orderby=Created desc&$top=20"));
    return response.value.map(item => this.mapJob(item));
  }

  public async retryJob(job: ProvisioningJob): Promise<void> {
    await this.merge(this.listItemsUrl('Provisioning Jobs', `(${job.id})`), {
      JobStatus: 'Dispatched',
      RetryCount: (job.retryCount || 0) + 1,
      ErrorJson: ''
    });
  }

  public async cancelJob(job: ProvisioningJob): Promise<void> {
    await this.merge(this.listItemsUrl('Provisioning Jobs', `(${job.id})`), {
      JobStatus: 'Cancelled',
      ErrorJson: JSON.stringify({
        cancelledBy: 'portal',
        cancelledAt: new Date().toISOString(),
        previousStatus: job.jobStatus
      })
    });
  }

  private mapJob(item: IProvisioningJobListItem): ProvisioningJob {
    return {
      id: item.Id,
      jobId: item.Title,
      jobType: item.JobType || '',
      parentTicketId: item.ParentTicketId || 0,
      parentRitmId: item.ParentRitmId,
      jobStatus: item.JobStatus || 'Proposed',
      callerUpn: item.CallerUpn || '',
      targetJson: item.TargetJson || '',
      argsJson: item.ArgsJson,
      correlationId: item.CorrelationId || '',
      servicePrincipal: item.ServicePrincipal,
      graphRequestId: item.GraphRequestId,
      errorJson: item.ErrorJson,
      retryCount: item.RetryCount,
      created: item.Created,
      modified: item.Modified
    };
  }
}
