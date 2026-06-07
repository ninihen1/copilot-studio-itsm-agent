import { RequestItem } from '../models/RequestItem';
import { Task } from '../models/Task';
import { ISharePointServiceContext, SharePointServiceBase } from './SharePointServiceBase';

interface IListResponse<T> {
  value: T[];
}

interface IRequestItemListItem {
  Id: number;
  Title?: string;
  RitmNumber?: string;
  ParentTicketId?: number;
  CatalogItemId?: number;
  CatalogItem?: unknown;
  RequestedFor?: unknown;
  RitmState?: RequestItem['ritmState'];
  Variables?: string;
  WorkNotes?: string;
  AssignmentGroup?: unknown;
  Created?: string;
  Modified?: string;
}

interface ITaskListItem {
  Id: number;
  Title?: string;
  TaskNumber?: string;
  ParentRitmId?: number;
  TaskState?: Task['taskState'];
  ShortDescription?: string;
  JobType?: string;
  LinkedJobId?: string;
  SortOrder?: number;
}

export class RequestService extends SharePointServiceBase {
  public constructor(context: ISharePointServiceContext) {
    super(context);
  }

  public async getRequestItemsForTicket(ticketId: number): Promise<RequestItem[]> {
    const select = '$select=Id,Title,RitmNumber,ParentTicketId,CatalogItemId,CatalogItem/Title,RequestedFor/Title,RequestedFor/EMail,RitmState,Variables,Created,Modified';
    const response = await this.get<IListResponse<IRequestItemListItem>>(this.listItemsUrl('Request Items', `?${select}&$expand=CatalogItem,RequestedFor&$filter=ParentTicketId eq ${ticketId}&$orderby=Created desc&$top=50`));
    return response.value.map(item => this.mapRequestItem(item));
  }

  /**
   * Hand-off queue for the IT Service Desk: RITMs On Hold that were routed to a
   * fulfilment group by the 3.2 hand-off lane (clarify RITMs have no AssignmentGroup).
   */
  public async getHandoffQueue(): Promise<RequestItem[]> {
    const select = '$select=Id,Title,RitmNumber,ParentTicketId,CatalogItemId,CatalogItem/Title,RequestedFor/Title,RequestedFor/EMail,AssignmentGroup/Title,AssignmentGroup/EMail,RitmState,Variables,WorkNotes,Created,Modified';
    const response = await this.get<IListResponse<IRequestItemListItem>>(this.listItemsUrl('Request Items', `?${select}&$expand=CatalogItem,RequestedFor,AssignmentGroup&$filter=RitmState eq 'On Hold'&$orderby=Modified desc&$top=100`));
    return response.value
      .filter(item => !!item.AssignmentGroup)
      .map(item => ({
        ...this.mapRequestItem(item),
        workNotes: item.WorkNotes,
        assignmentGroup: this.lookupValue(item.AssignmentGroup)
      }));
  }

  /**
   * Service-desk closure of a hand-off RITM, written directly in the fulfiller's
   * user context (no flow / no SAS). Downstream ticket-resolve + requester notify
   * are handled by the closure flow reacting to this state change.
   */
  public async closeRitm(ritmId: number, ritmState: RequestItem['ritmState'], closeCode: string, closeNotes: string): Promise<void> {
    await this.merge(this.listItemsUrl('Request Items', `(${ritmId})`), {
      RitmState: ritmState,
      CloseCode: closeCode,
      CloseNotes: closeNotes,
      ClosedDate: new Date().toISOString()
    });
  }

  public async getTasksForRitm(ritmId: number): Promise<Task[]> {
    const response = await this.get<IListResponse<ITaskListItem>>(this.listItemsUrl('Tasks', `?$select=Id,Title,TaskNumber,ParentRitmId,TaskState,ShortDescription,JobType,LinkedJobId,SortOrder&$filter=ParentRitmId eq ${ritmId}&$orderby=SortOrder asc,Created asc&$top=50`));
    return response.value.map(item => ({
      id: item.Id,
      taskNumber: item.TaskNumber || item.Title || `SCTASK-${item.Id}`,
      parentRitmId: item.ParentRitmId || 0,
      taskState: item.TaskState || 'Open',
      shortDescription: item.ShortDescription || '',
      jobType: item.JobType,
      linkedJobId: item.LinkedJobId,
      sortOrder: item.SortOrder
    }));
  }

  private mapRequestItem(item: IRequestItemListItem): RequestItem {
    return {
      id: item.Id,
      ritmNumber: item.RitmNumber || item.Title || `RITM-${item.Id}`,
      parentTicketId: item.ParentTicketId || 0,
      catalogItemId: item.CatalogItemId || 0,
      catalogItem: this.lookupValue(item.CatalogItem),
      requestedFor: this.userValue(item.RequestedFor) || '',
      ritmState: item.RitmState || 'Pending Approval',
      variables: item.Variables,
      created: item.Created,
      modified: item.Modified
    };
  }
}
