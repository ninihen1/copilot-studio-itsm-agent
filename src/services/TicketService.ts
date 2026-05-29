import { Ticket, TicketType } from '../models/Ticket';
import { ISharePointServiceContext, SharePointServiceBase } from './SharePointServiceBase';

interface IListResponse<T> {
  value: T[];
}

interface IPeoplePickerSearchResponse {
  value: string;
}

interface IClientPeoplePickerEntity {
  Key?: string;
  DisplayText?: string;
  EntityData?: {
    Email?: string;
  };
}

interface ITicketListItem {
  Id: number;
  Title: string;
  TicketType?: Ticket['ticketType'];
  TicketState?: Ticket['ticketState'];
  ShortDescription?: string;
  Description?: string;
  Priority?: string;
  Impact?: string;
  Urgency?: string;
  CloseCode?: string;
  CloseNotes?: string;
  ClosedDate?: string;
  WorkNotes?: string;
  TicketSource?: string;
  ConfidentialityLevel?: string;
  TicketTypeValidated?: boolean;
  TicketTypeValidationStatus?: string;
  TicketTypeValidationReason?: string;
  SuggestedTicketType?: Ticket['suggestedTicketType'];
  TypeOverrideConfirmed?: boolean;
  EscalationFlag?: boolean;
  TicketFollowers?: Array<{ Id?: number; Title?: string; EMail?: string }> | { results?: Array<{ Id?: number; Title?: string; EMail?: string }> };
  SlaStatus?: Ticket['slaStatus'];
  SlaPercentElapsed?: number;
  Created?: string;
  Modified?: string;
  CategoryRef?: unknown;
  Subcategory?: unknown;
  Caller?: unknown;
}

export interface DashboardMetrics {
  myOpenTickets: number;
  pendingApprovals: number;
  serviceHealthAlerts: number;
  kbSuggestions: number;
  licenseCostRows: number;
}

export interface CreateIncidentInput {
  ticketType: Extract<TicketType, 'Incident' | 'Request'>;
  shortDescription: string;
  description: string;
  categoryId: number;
  subcategoryId?: number;
  catalogItemId?: number;
  requestedForUserId?: number;
  requestedForUserLogin?: string;
  typeOverrideConfirmed?: boolean;
  impact: string;
  urgency: string;
}

export interface PeoplePickerUser {
  loginName: string;
  displayName: string;
  email?: string;
}

export class TicketService extends SharePointServiceBase {
  public constructor(context: ISharePointServiceContext) {
    super(context);
  }

  public async getMyTickets(_userEmail?: string): Promise<Ticket[]> {
    const select = '$select=Id,Title,TicketType,TicketState,ShortDescription,Description,Priority,Impact,Urgency,CloseCode,CloseNotes,ClosedDate,WorkNotes,TicketSource,ConfidentialityLevel,TicketTypeValidated,TicketTypeValidationStatus,TicketTypeValidationReason,SuggestedTicketType,TypeOverrideConfirmed,EscalationFlag,TicketFollowers/Id,SlaStatus,SlaPercentElapsed,Created,Modified,CategoryRef/Title,Subcategory/Title,Caller/Title,Caller/EMail';
    const expand = '$expand=CategoryRef,Subcategory,Caller,TicketFollowers';
    const order = '$orderby=Created desc';
    const top = '$top=20';

    const response = await this.get<IListResponse<ITicketListItem>>(this.listItemsUrl('Tickets', `?${select}&${expand}&${order}&${top}`));
    return response.value.map(item => this.mapTicket(item));
  }

  public async getTicket(id: number): Promise<Ticket | undefined> {
    const select = '$select=Id,Title,TicketType,TicketState,ShortDescription,Description,Priority,Impact,Urgency,CloseCode,CloseNotes,ClosedDate,WorkNotes,TicketSource,ConfidentialityLevel,TicketTypeValidated,TicketTypeValidationStatus,TicketTypeValidationReason,SuggestedTicketType,TypeOverrideConfirmed,EscalationFlag,TicketFollowers/Id,SlaStatus,SlaPercentElapsed,Created,Modified,CategoryRef/Title,Subcategory/Title,Caller/Title,Caller/EMail';
    const expand = '$expand=CategoryRef,Subcategory,Caller,TicketFollowers';
    const response = await this.get<ITicketListItem>(this.listItemsUrl('Tickets', `(${id})?${select}&${expand}`));
    return this.mapTicket(response);
  }

  public async getDashboardMetrics(userEmail?: string): Promise<DashboardMetrics> {
    const [tickets, pendingApprovals, failedJobs, publishedKb] = await Promise.all([
      this.getMyTickets(userEmail),
      this.countByFilter('Request Items', "RitmState eq 'Pending Approval'"),
      this.countByFilter('Provisioning Jobs', "JobStatus eq 'Failed'"),
      this.countByFilter('Knowledge Base', "ArticleStatus eq 'Published'")
    ]);

    return {
      myOpenTickets: tickets.filter(ticket => ['Resolved', 'Closed', 'Cancelled'].indexOf(ticket.ticketState) === -1).length,
      pendingApprovals,
      serviceHealthAlerts: failedJobs,
      kbSuggestions: publishedKb,
      licenseCostRows: 0
    };
  }

  public async createIncident(input: CreateIncidentInput): Promise<Ticket> {
    const callerId = await this.getCurrentUserId();
    const requestedForUserId = input.requestedForUserId || (input.requestedForUserLogin ? await this.ensureUserId(input.requestedForUserLogin) : callerId);
    const ticketNumber = this.generateTicketNumber(input.ticketType === 'Request' ? 'REQ' : 'INC');
    const payload: Record<string, unknown> = {
      Title: ticketNumber,
      ShortDescription: input.shortDescription,
      Description: input.description,
      TicketType: input.ticketType,
      TicketState: 'New',
      TicketSource: 'Portal',
      CallerId: callerId,
      RequestedForUserId: requestedForUserId,
      CategoryRefId: input.categoryId,
      Impact: input.impact,
      Urgency: input.urgency,
      ConfidentialityLevel: 'Public',
      TicketTypeValidated: false,
      TicketTypeValidationStatus: 'Pending',
      TypeOverrideConfirmed: !!input.typeOverrideConfirmed
    };

    if (input.subcategoryId) {
      payload.SubcategoryId = input.subcategoryId;
    }
    if (input.catalogItemId) {
      payload.SelectedCatalogItemId = input.catalogItemId;
    }

    const created = await this.post<ITicketListItem>(this.listItemsUrl('Tickets'), payload);
    const ticket = await this.getTicket(created.Id);
    return ticket || this.mapTicket(created);
  }

  public async searchPeople(query: string): Promise<PeoplePickerUser[]> {
    if (!query.trim()) {
      return [];
    }

    const response = await this.post<IPeoplePickerSearchResponse>('/_api/SP.UI.ApplicationPages.ClientPeoplePickerWebServiceInterface.clientPeoplePickerSearchUser', {
      queryParams: {
        QueryString: query,
        MaximumEntitySuggestions: 8,
        AllowEmailAddresses: true,
        AllowMultipleEntities: false,
        PrincipalSource: 15,
        PrincipalType: 1
      }
    });
    const entities = JSON.parse(response.value || '[]') as IClientPeoplePickerEntity[];
    return entities
      .filter(entity => !!entity.Key)
      .map(entity => ({
        loginName: entity.Key as string,
        displayName: entity.DisplayText || entity.EntityData?.Email || entity.Key as string,
        email: entity.EntityData?.Email
      }));
  }

  public async addComment(ticket: Ticket, comment: string): Promise<void> {
    const stamped = `Portal comment at ${new Date().toISOString()}: ${comment}`;
    await this.merge(this.listItemsUrl('Tickets', `(${ticket.id})`), {
      Comments: stamped,
      WorkNotes: stamped
    });
  }

  public async toggleFollow(ticket: Ticket): Promise<boolean> {
    const currentUserId = await this.getCurrentUserId();
    const current = await this.get<ITicketListItem>(this.listItemsUrl('Tickets', `(${ticket.id})?$select=Id,TicketFollowers/Id&$expand=TicketFollowers`));
    const followerIds = this.userIds(current.TicketFollowers);
    const isFollowing = followerIds.indexOf(currentUserId) >= 0;
    const nextIds = isFollowing ? followerIds.filter(id => id !== currentUserId) : followerIds.concat(currentUserId);

    await this.merge(this.listItemsUrl('Tickets', `(${ticket.id})`), {
      TicketFollowersId: {
        results: nextIds
      }
    });

    return !isFollowing;
  }

  public async escalate(ticket: Ticket): Promise<void> {
    await this.merge(this.listItemsUrl('Tickets', `(${ticket.id})`), {
      EscalationFlag: true,
      WorkNotes: `Portal escalation requested at ${new Date().toISOString()}.`
    });
  }

  private async countByFilter(listTitle: string, filter: string): Promise<number> {
    const response = await this.get<IListResponse<{ Id: number }>>(this.listItemsUrl(listTitle, `?$select=Id&$filter=${filter}&$top=5000`));
    return response.value.length;
  }

  private mapTicket(item: ITicketListItem): Ticket {
    return {
      id: item.Id,
      title: item.Title,
      ticketType: item.TicketType || 'Incident',
      ticketState: item.TicketState || 'New',
      shortDescription: item.ShortDescription || item.Title,
      description: item.Description,
      category: this.lookupValue(item.CategoryRef),
      subcategory: this.lookupValue(item.Subcategory),
      caller: this.userValue(item.Caller),
      priority: item.Priority,
      impact: item.Impact,
      urgency: item.Urgency,
      closeCode: item.CloseCode,
      closeNotes: item.CloseNotes,
      closedDate: item.ClosedDate,
      workNotes: item.WorkNotes,
      ticketSource: item.TicketSource,
      confidentialityLevel: item.ConfidentialityLevel,
      ticketTypeValidated: item.TicketTypeValidated,
      ticketTypeValidationStatus: item.TicketTypeValidationStatus,
      ticketTypeValidationReason: item.TicketTypeValidationReason,
      suggestedTicketType: item.SuggestedTicketType,
      typeOverrideConfirmed: item.TypeOverrideConfirmed,
      escalationFlag: item.EscalationFlag,
      ticketFollowerIds: this.userIds(item.TicketFollowers),
      slaStatus: item.SlaStatus,
      slaPercentElapsed: item.SlaPercentElapsed,
      created: item.Created,
      modified: item.Modified
    };
  }

  private generateTicketNumber(prefix: string): string {
    const now = new Date();
    const stamp = [
      now.getUTCFullYear().toString().slice(-2),
      this.pad2(now.getUTCMonth() + 1),
      this.pad2(now.getUTCDate()),
      this.pad2(now.getUTCHours()),
      this.pad2(now.getUTCMinutes()),
      this.pad2(now.getUTCSeconds())
    ].join('');
    const suffix = Math.random().toString(16).slice(2, 6);
    return `${prefix}${stamp}${suffix}`;
  }

  private pad2(value: number): string {
    return value < 10 ? `0${value}` : String(value);
  }

  private userIds(users?: Array<{ Id?: number }> | { results?: Array<{ Id?: number }> }): number[] {
    if (!users) {
      return [];
    }
    const values = Array.isArray(users) ? users : users.results || [];
    return values.map(user => user.Id).filter((id): id is number => typeof id === 'number');
  }
}
