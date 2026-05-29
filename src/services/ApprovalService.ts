import { RequestItem } from '../models/RequestItem';
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
  Created?: string;
  Modified?: string;
}

export class ApprovalService extends SharePointServiceBase {
  public constructor(context: ISharePointServiceContext) {
    super(context);
  }

  public async getPendingApprovals(): Promise<RequestItem[]> {
    const select = '$select=Id,Title,RitmNumber,ParentTicketId,CatalogItemId,CatalogItem/Title,RequestedFor/Title,RequestedFor/EMail,RitmState,Variables,Created,Modified';
    const response = await this.get<IListResponse<IRequestItemListItem>>(this.listItemsUrl('Request Items', `?${select}&$expand=CatalogItem,RequestedFor&$filter=RitmState eq 'Pending Approval'&$orderby=Created desc&$top=50`));

    return response.value.map(item => ({
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
    }));
  }

  public async approve(requestItem: RequestItem, comment?: string): Promise<void> {
    await this.merge(this.listItemsUrl('Request Items', `(${requestItem.id})`), {
      RitmState: 'Approved',
      WorkNotes: `Portal approval granted at ${new Date().toISOString()}${comment ? `: ${comment}` : '.'}`
    });
  }

  public async reject(requestItem: RequestItem, comment?: string): Promise<void> {
    await this.merge(this.listItemsUrl('Request Items', `(${requestItem.id})`), {
      RitmState: 'Closed Incomplete',
      CloseCode: 'Rejected',
      CloseNotes: comment || 'Rejected from portal approval queue.',
      WorkNotes: `Portal approval rejected at ${new Date().toISOString()}${comment ? `: ${comment}` : '.'}`
    });
  }

  public async addComment(requestItem: RequestItem, comment: string): Promise<void> {
    await this.merge(this.listItemsUrl('Request Items', `(${requestItem.id})`), {
      WorkNotes: `Portal approval comment at ${new Date().toISOString()}: ${comment}`
    });
  }
}
