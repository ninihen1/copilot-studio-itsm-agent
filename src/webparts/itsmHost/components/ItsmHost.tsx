import * as React from 'react';
import styles from './ItsmHost.module.scss';
import { IItsmHostProps } from './IItsmHostProps';
import { HomeView } from '../../../routes/HomeView';
import { SubmitIncidentView } from '../../../routes/SubmitIncidentView';
import { CatalogView } from '../../../routes/CatalogView';
import { TicketDetailView } from '../../../routes/TicketDetailView';
import { ApprovalsView } from '../../../routes/ApprovalsView';
import { KnowledgeView } from '../../../routes/KnowledgeView';
import { AdminView } from '../../../routes/AdminView';
import { SubcategoriesView } from '../../../routes/SubcategoriesView';
import { ServiceDeskQueueView, CloseDisposition } from '../../../routes/ServiceDeskQueueView';
import { WorkItemDetailDialog, WorkItemDetailKind } from '../../../components/WorkItemDetailDialog';
import { CatalogDetailDialog } from '../../../components/CatalogDetailDialog';
import { CatalogItem } from '../../../models/CatalogItem';
import { Category } from '../../../models/Category';
import { LicenseCost } from '../../../models/LicenseCost';
import { ProvisioningJob } from '../../../models/ProvisioningJob';
import { RequestItem } from '../../../models/RequestItem';
import { Subcategory } from '../../../models/Subcategory';
import { Task } from '../../../models/Task';
import { Ticket } from '../../../models/Ticket';
import { ApprovalService } from '../../../services/ApprovalService';
import { CategoryService } from '../../../services/CategoryService';
import { CatalogService } from '../../../services/CatalogService';
import { DashboardMetrics, TicketService } from '../../../services/TicketService';
import { JobAuditService } from '../../../services/JobAuditService';
import { KnowledgeArticle, KnowledgeService } from '../../../services/KnowledgeService';
import { LicenseCostService } from '../../../services/LicenseCostService';
import { RequestService } from '../../../services/RequestService';
import { SubcategoryService } from '../../../services/SubcategoryService';

type RouteKey = 'home' | 'submit' | 'catalog' | 'subcategories' | 'tickets' | 'approvals' | 'queue' | 'knowledge' | 'admin';

interface IItmsHostState {
  route: RouteKey;
  isLoading: boolean;
  isSubmittingTicket: boolean;
  loadError?: string;
  metrics?: DashboardMetrics;
  tickets: Ticket[];
  categories: Category[];
  catalogItems: CatalogItem[];
  licenseCosts: LicenseCost[];
  licenseCostCount: number;
  licensePickerOptions: LicenseCost[];
  subcategories: Subcategory[];
  approvals: RequestItem[];
  handoffQueue: RequestItem[];
  closingRitmId?: number;
  knowledgeArticles: KnowledgeArticle[];
  failedJobs: ProvisioningJob[];
  detailIsOpen: boolean;
  detailIsLoading: boolean;
  detailKind?: WorkItemDetailKind;
  detailError?: string;
  detailTicket?: Ticket;
  detailRequestItem?: RequestItem;
  detailJob?: ProvisioningJob;
  detailRequestItems: RequestItem[];
  detailJobs: ProvisioningJob[];
  detailTasks: Task[];
  catalogDetailIsOpen: boolean;
  detailCatalogItem?: CatalogItem;
}

interface ILoadResult<T> {
  value: T;
  error?: string;
}

export default class ItsmHost extends React.Component<IItsmHostProps, IItmsHostState> {
  public constructor(props: IItsmHostProps) {
    super(props);
    this.state = {
      route: 'home',
      isLoading: true,
      isSubmittingTicket: false,
      tickets: [],
      categories: [],
      catalogItems: [],
      licenseCosts: [],
      licenseCostCount: 0,
      licensePickerOptions: [],
      subcategories: [],
      approvals: [],
      handoffQueue: [],
      knowledgeArticles: [],
      failedJobs: [],
      detailIsOpen: false,
      detailIsLoading: false,
      detailRequestItems: [],
      detailJobs: [],
      detailTasks: [],
      catalogDetailIsOpen: false
    };
  }

  public componentDidMount(): void {
    this._loadData().catch(error => {
      this.setState({
        isLoading: false,
        loadError: error instanceof Error ? error.message : 'Unable to load SharePoint data.'
      });
    });
  }

  public render(): React.ReactElement<IItsmHostProps> {
    return (
      <section className={styles.itsmHost}>
        <header className={styles.topbar}>
          <div className={styles.waffle} aria-label="Microsoft 365 app launcher">
            <span /><span /><span /><span /><span /><span /><span /><span /><span />
          </div>
          <div className={styles.brand}><span className={styles.brandMark}>IT</span><span>ITSM Service Portal</span></div>
          <div className={styles.search}><input placeholder="Search tickets, catalog, knowledge base" /></div>
          <div className={styles.userZone}>
            <span className={styles.user}>{this.props.userDisplayName}</span>
            <span className={styles.avatar}>{this._initials(this.props.userDisplayName)}</span>
          </div>
        </header>
        <div className={styles.shell}>
          <nav className={styles.rail} aria-label="ITSM navigation">
            <div className={styles.railSection}>
              <div className={styles.railLabel}>Workspace</div>
              {this._navItem('home', 'H', 'Home')}
              {this._navItem('submit', '+', 'Submit ticket')}
              {this._navItem('tickets', 'T', 'My tickets')}
            </div>
            <div className={styles.railSection}>
              <div className={styles.railLabel}>Services</div>
              {this._navItem('catalog', 'C', 'Service catalog')}
              {this._navItem('subcategories', 'S', 'Subcategories')}
              {this._navItem('knowledge', '?', 'Knowledge base')}
              {this._navItem('approvals', 'A', 'Approvals')}
              {this._navItem('queue', 'Q', 'Service desk')}
            </div>
            <div className={styles.railSection}>
              <div className={styles.railLabel}>Operations</div>
              {this._navItem('admin', 'O', 'Admin')}
            </div>
          </nav>
          <main className={styles.page}><div className={styles.pageInner}>{this._renderRoute()}</div></main>
        </div>
        <WorkItemDetailDialog
          isOpen={this.state.detailIsOpen}
          isLoading={this.state.detailIsLoading}
          error={this.state.detailError}
          kind={this.state.detailKind}
          ticket={this.state.detailTicket}
          requestItem={this.state.detailRequestItem}
          job={this.state.detailJob}
          requestItems={this.state.detailRequestItems}
          jobs={this.state.detailJobs}
          tasks={this.state.detailTasks}
          onDismiss={this._closeDetail}
          onAddTicketComment={this._addTicketComment}
          onToggleTicketFollow={this._toggleTicketFollow}
          onEscalateTicket={this._escalateTicket}
          onApproveRequest={this._approveRequest}
          onRejectRequest={this._rejectRequest}
          onAddApprovalComment={this._addApprovalComment}
          onRetryJob={this._retryJob}
          onCancelJob={this._cancelJob}
        />
        <CatalogDetailDialog
          isOpen={this.state.catalogDetailIsOpen}
          item={this.state.detailCatalogItem}
          onDismiss={this._closeCatalogDetail}
        />
      </section>
    );
  }

  private _navItem(route: RouteKey, icon: string, label: string): React.ReactElement {
    const active = this.state.route === route ? styles.active : '';
    return (
      <button className={`${styles.railLink} ${active}`} onClick={() => this._navigate(route)}>
        <span className={styles.railIcon}>{icon}</span>
        {label}
      </button>
    );
  }

  private _navigate = (route: RouteKey): void => {
    this.setState({ route });
    // The hand-off queue must reflect current state every time it is opened,
    // not just what was loaded on initial mount.
    if (route === 'queue') {
      void this._refreshQueue();
    }
  };

  private _refreshQueue = async (): Promise<void> => {
    try {
      const requestService = new RequestService({ siteUrl: this.props.siteUrl, spHttpClient: this.props.spHttpClient });
      const handoffQueue = await requestService.getHandoffQueue();
      this.setState({ handoffQueue });
    } catch (error) {
      this.setState({ loadError: error instanceof Error ? error.message : 'Could not refresh the service desk queue.' });
    }
  };

  private _initials(displayName: string): string {
    return displayName
      .split(' ')
      .filter(Boolean)
      .slice(0, 2)
      .map(part => part.charAt(0).toUpperCase())
      .join('') || 'IT';
  }

  private _renderRoute(): React.ReactElement {
    switch (this.state.route) {
      case 'submit':
        return <SubmitIncidentView categories={this.state.categories} catalogItems={this.state.catalogItems} subcategories={this.state.subcategories} licenses={this.state.licensePickerOptions} isSubmitting={this.state.isSubmittingTicket} currentUserDisplayName={this.props.userDisplayName} currentUserEmail={this.props.userEmail} onResolvePeople={this._resolvePeople} onSubmit={this._submitIncident} />;
      case 'catalog':
        return <CatalogView items={this.state.catalogItems} licenseCosts={this.state.licenseCosts} isLoading={this.state.isLoading} onOpenItem={this._openCatalogDetail} />;
      case 'subcategories':
        return <SubcategoriesView subcategories={this.state.subcategories} isLoading={this.state.isLoading} />;
      case 'tickets':
        return <TicketDetailView tickets={this.state.tickets} isLoading={this.state.isLoading} onOpenTicket={this._openTicketDetail} />;
      case 'approvals':
        return <ApprovalsView approvals={this.state.approvals} isLoading={this.state.isLoading} onOpenApproval={this._openApprovalDetail} />;
      case 'queue':
        return <ServiceDeskQueueView queue={this.state.handoffQueue} isLoading={this.state.isLoading} busyRitmId={this.state.closingRitmId} onClose={this._closeHandoff} />;
      case 'knowledge':
        return <KnowledgeView articles={this.state.knowledgeArticles} isLoading={this.state.isLoading} />;
      case 'admin':
        return <AdminView metrics={this.state.metrics} failedJobs={this.state.failedJobs} licenseCosts={this.state.licenseCosts} licenseCostCount={this.state.licenseCostCount} isLoading={this.state.isLoading} onOpenJob={this._openJobDetail} />;
      case 'home':
      default:
        return <HomeView metrics={this.state.metrics} tickets={this.state.tickets} error={this.state.loadError} isLoading={this.state.isLoading} onOpenTicket={this._openTicketDetail} />;
    }
  }

  private async _loadData(): Promise<void> {
    const serviceContext = {
      siteUrl: this.props.siteUrl,
      spHttpClient: this.props.spHttpClient
    };
    const ticketService = new TicketService(serviceContext);
    const categoryService = new CategoryService(serviceContext);
    const catalogService = new CatalogService(serviceContext);
    const subcategoryService = new SubcategoryService(serviceContext);
    const approvalService = new ApprovalService(serviceContext);
    const requestService = new RequestService(serviceContext);
    const knowledgeService = new KnowledgeService(serviceContext);
    const jobAuditService = new JobAuditService(serviceContext);
    const licenseCostService = new LicenseCostService(serviceContext);

    const [metrics, tickets, categories, catalogItems, subcategories, approvals, knowledgeArticles, failedJobs, licenseCosts, licenseCostCount, licensePickerOptions, handoffQueue] = await Promise.all([
      this._loadPart('dashboard metrics', ticketService.getDashboardMetrics(this.props.userEmail), {
        myOpenTickets: 0,
        pendingApprovals: 0,
        serviceHealthAlerts: 0,
        kbSuggestions: 0,
        licenseCostRows: 0
      }),
      this._loadPart('tickets', ticketService.getMyTickets(this.props.userEmail), []),
      this._loadPart('categories', categoryService.getActiveCategories(), []),
      this._loadPart('service catalog', catalogService.getActiveItems(), []),
      this._loadPart('subcategories', subcategoryService.getActiveSubcategories(), []),
      this._loadPart('approvals', approvalService.getPendingApprovals(), []),
      this._loadPart('knowledge base', knowledgeService.search(''), []),
      this._loadPart('failed jobs', jobAuditService.getFailedJobs(), []),
      this._loadPart('license costs', licenseCostService.getRecentCosts(25), []),
      this._loadPart('license cost count', licenseCostService.getCostCount(), 0),
      this._loadPart('license picker', licenseCostService.getForPicker(), []),
      this._loadPart('hand-off queue', requestService.getHandoffQueue(), [])
    ]);
    const errors = [metrics, tickets, categories, catalogItems, subcategories, approvals, knowledgeArticles, failedJobs, licenseCosts, licenseCostCount, licensePickerOptions, handoffQueue]
      .map(result => result.error)
      .filter(Boolean);

    const mergedMetrics = {
      ...metrics.value,
      licenseCostRows: licenseCostCount.value
    };

    this.setState({
      isLoading: false,
      loadError: errors.length ? `Some SharePoint data could not load: ${errors.join(' | ')}` : undefined,
      metrics: mergedMetrics,
      tickets: tickets.value,
      categories: categories.value,
      catalogItems: catalogItems.value,
      licenseCosts: licenseCosts.value,
      licenseCostCount: licenseCostCount.value,
      licensePickerOptions: licensePickerOptions.value,
      subcategories: subcategories.value,
      approvals: approvals.value,
      handoffQueue: handoffQueue.value,
      knowledgeArticles: knowledgeArticles.value,
      failedJobs: failedJobs.value
    });
  }

  private _closeHandoff = async (ritm: RequestItem, disposition: CloseDisposition, closeNotes: string): Promise<void> => {
    this.setState({ closingRitmId: ritm.id, loadError: undefined });
    const serviceContext = { siteUrl: this.props.siteUrl, spHttpClient: this.props.spHttpClient };
    const requestService = new RequestService(serviceContext);
    const ticketService = new TicketService(serviceContext);
    const ritmState = disposition === 'declined' ? 'Closed Incomplete' : 'Closed Complete';
    const ticketState = disposition === 'declined' ? 'Cancelled' : 'Closed';
    const closeCode = disposition === 'declined' ? 'Rejected' : 'Fulfilled';
    const notes = closeNotes && closeNotes.trim().length ? closeNotes.trim() : (disposition === 'declined' ? 'Declined by the IT service desk.' : 'Fulfilled by the IT service desk.');

    try {
      await requestService.closeRitm(ritm.id, ritmState, closeCode, notes);
      if (ritm.parentTicketId) {
        await ticketService.resolveTicket(ritm.parentTicketId, ticketState, closeCode, notes);
      }
      const handoffQueue = await requestService.getHandoffQueue();
      this.setState({
        closingRitmId: undefined,
        handoffQueue,
        loadError: `RITM #${ritm.id} ${ritmState.toLowerCase()}${ritm.parentTicketId ? ` · ticket #${ritm.parentTicketId} ${ticketState.toLowerCase()}` : ''}.`
      });
    } catch (error) {
      this.setState({
        closingRitmId: undefined,
        loadError: error instanceof Error ? error.message : 'Closing the request failed.'
      });
    }
  };

  private _submitIncident = async (input: Parameters<TicketService['createIncident']>[0]): Promise<void> => {
    this.setState({ isSubmittingTicket: true, loadError: undefined });
    const ticketService = new TicketService({
      siteUrl: this.props.siteUrl,
      spHttpClient: this.props.spHttpClient
    });

    try {
      const created = await ticketService.createIncident(input);
      const tickets = await ticketService.getMyTickets(this.props.userEmail);
      this.setState({
        isSubmittingTicket: false,
        route: 'tickets',
        tickets,
        loadError: `Ticket ${created.title} created.`
      });
    } catch (error) {
      this.setState({
        isSubmittingTicket: false,
        loadError: error instanceof Error ? error.message : 'Ticket submission failed.'
      });
      throw error;
    }
  };

  private _resolvePeople = async (query: string) => {
    const ticketService = new TicketService({
      siteUrl: this.props.siteUrl,
      spHttpClient: this.props.spHttpClient
    });
    return ticketService.searchPeople(query);
  };

  private _openTicketDetail = (ticket: Ticket): void => {
    this.setState({
      detailIsOpen: true,
      detailIsLoading: true,
      detailKind: 'ticket',
      detailError: undefined,
      detailTicket: ticket,
      detailRequestItem: undefined,
      detailJob: undefined,
      detailRequestItems: [],
      detailJobs: [],
      detailTasks: []
    });
    this._loadDetail('ticket', ticket).catch(error => this._setDetailError(error));
  };

  private _openApprovalDetail = (requestItem: RequestItem): void => {
    this.setState({
      detailIsOpen: true,
      detailIsLoading: true,
      detailKind: 'approval',
      detailError: undefined,
      detailTicket: undefined,
      detailRequestItem: requestItem,
      detailJob: undefined,
      detailRequestItems: [requestItem],
      detailJobs: [],
      detailTasks: []
    });
    this._loadDetail('approval', requestItem).catch(error => this._setDetailError(error));
  };

  private _openJobDetail = (job: ProvisioningJob): void => {
    this.setState({
      detailIsOpen: true,
      detailIsLoading: true,
      detailKind: 'job',
      detailError: undefined,
      detailTicket: undefined,
      detailRequestItem: undefined,
      detailJob: job,
      detailRequestItems: [],
      detailJobs: [job],
      detailTasks: []
    });
    this._loadDetail('job', job).catch(error => this._setDetailError(error));
  };

  private _closeDetail = (): void => {
    this.setState({ detailIsOpen: false });
  };

  private _openCatalogDetail = (item: CatalogItem): void => {
    this.setState({ catalogDetailIsOpen: true, detailCatalogItem: item });
  };

  private _closeCatalogDetail = (): void => {
    this.setState({ catalogDetailIsOpen: false });
  };

  private async _loadDetail(kind: WorkItemDetailKind, item: Ticket | RequestItem | ProvisioningJob): Promise<void> {
    const serviceContext = {
      siteUrl: this.props.siteUrl,
      spHttpClient: this.props.spHttpClient
    };
    const ticketService = new TicketService(serviceContext);
    const requestService = new RequestService(serviceContext);
    const jobService = new JobAuditService(serviceContext);

    let ticket: Ticket | undefined;
    let requestItem: RequestItem | undefined;
    let job: ProvisioningJob | undefined;
    let requestItems: RequestItem[] = [];
    let jobs: ProvisioningJob[] = [];

    if (kind === 'ticket') {
      const selectedTicket = item as Ticket;
      ticket = await ticketService.getTicket(selectedTicket.id) || selectedTicket;
      requestItems = await this._safeDetailPart(() => requestService.getRequestItemsForTicket(selectedTicket.id), []);
      jobs = await this._safeDetailPart(() => jobService.getJobsForTicket(selectedTicket.id), []);
    } else if (kind === 'approval') {
      const selectedRequestItem = item as RequestItem;
      requestItem = selectedRequestItem;
      if (selectedRequestItem.parentTicketId) {
        ticket = await this._safeDetailPart(() => ticketService.getTicket(selectedRequestItem.parentTicketId), undefined);
        requestItems = await this._safeDetailPart(() => requestService.getRequestItemsForTicket(selectedRequestItem.parentTicketId), [selectedRequestItem]);
        jobs = await this._safeDetailPart(() => jobService.getJobsForTicket(selectedRequestItem.parentTicketId), []);
        requestItem = requestItems.find(current => current.id === selectedRequestItem.id) || selectedRequestItem;
      } else {
        requestItems = [selectedRequestItem];
      }
    } else {
      const selectedJob = item as ProvisioningJob;
      job = selectedJob;
      if (selectedJob.parentTicketId) {
        ticket = await this._safeDetailPart(() => ticketService.getTicket(selectedJob.parentTicketId), undefined);
        requestItems = await this._safeDetailPart(() => requestService.getRequestItemsForTicket(selectedJob.parentTicketId), []);
        jobs = await this._safeDetailPart(() => jobService.getJobsForTicket(selectedJob.parentTicketId), [selectedJob]);
        job = jobs.find(current => current.id === selectedJob.id) || selectedJob;
      } else {
        jobs = [selectedJob];
      }
    }

    const taskGroups = await Promise.all(requestItems.map(ritm => this._safeDetailPart(() => requestService.getTasksForRitm(ritm.id), [])));
    const tasks = taskGroups.reduce((all, group) => all.concat(group), [] as Task[]);

    this.setState({
      detailIsLoading: false,
      detailTicket: ticket,
      detailRequestItem: requestItem,
      detailJob: job,
      detailRequestItems: requestItems,
      detailJobs: jobs,
      detailTasks: tasks
    });
  }

  private async _safeDetailPart<T>(loader: () => Promise<T>, fallback: T): Promise<T> {
    try {
      return await loader();
    } catch {
      return fallback;
    }
  }

  private _setDetailError(error: unknown): void {
    this.setState({
      detailIsLoading: false,
      detailError: error instanceof Error ? error.message : 'Unable to load detail records.'
    });
  }

  private _addTicketComment = async (ticket: Ticket, comment: string): Promise<void> => {
    const service = new TicketService({ siteUrl: this.props.siteUrl, spHttpClient: this.props.spHttpClient });
    await service.addComment(ticket, comment);
    await this._refreshTicketDetail(ticket.id);
  };

  private _toggleTicketFollow = async (ticket: Ticket): Promise<void> => {
    const service = new TicketService({ siteUrl: this.props.siteUrl, spHttpClient: this.props.spHttpClient });
    await service.toggleFollow(ticket);
    await this._refreshTicketDetail(ticket.id);
  };

  private _escalateTicket = async (ticket: Ticket): Promise<void> => {
    const service = new TicketService({ siteUrl: this.props.siteUrl, spHttpClient: this.props.spHttpClient });
    await service.escalate(ticket);
    await this._refreshTicketDetail(ticket.id);
  };

  private _approveRequest = async (requestItem: RequestItem, comment?: string): Promise<void> => {
    const service = new ApprovalService({ siteUrl: this.props.siteUrl, spHttpClient: this.props.spHttpClient });
    await service.approve(requestItem, comment);
    await this._refreshApprovalDetail(requestItem);
  };

  private _rejectRequest = async (requestItem: RequestItem, comment?: string): Promise<void> => {
    const service = new ApprovalService({ siteUrl: this.props.siteUrl, spHttpClient: this.props.spHttpClient });
    await service.reject(requestItem, comment);
    await this._refreshApprovalDetail(requestItem);
  };

  private _addApprovalComment = async (requestItem: RequestItem, comment: string): Promise<void> => {
    const service = new ApprovalService({ siteUrl: this.props.siteUrl, spHttpClient: this.props.spHttpClient });
    await service.addComment(requestItem, comment);
    await this._refreshApprovalDetail(requestItem);
  };

  private _retryJob = async (job: ProvisioningJob): Promise<void> => {
    const service = new JobAuditService({ siteUrl: this.props.siteUrl, spHttpClient: this.props.spHttpClient });
    await service.retryJob(job);
    await this._refreshJobDetail(job);
  };

  private _cancelJob = async (job: ProvisioningJob): Promise<void> => {
    const service = new JobAuditService({ siteUrl: this.props.siteUrl, spHttpClient: this.props.spHttpClient });
    await service.cancelJob(job);
    await this._refreshJobDetail(job);
  };

  private async _refreshTicketDetail(ticketId: number): Promise<void> {
    const service = new TicketService({ siteUrl: this.props.siteUrl, spHttpClient: this.props.spHttpClient });
    const ticket = await service.getTicket(ticketId);
    if (ticket) {
      await this._loadDetail('ticket', ticket);
    }
  }

  private async _refreshApprovalDetail(requestItem: RequestItem): Promise<void> {
    await this._loadDetail('approval', requestItem);
  }

  private async _refreshJobDetail(job: ProvisioningJob): Promise<void> {
    await this._loadDetail('job', job);
  }

  private async _loadPart<T>(label: string, promise: Promise<T>, fallback: T): Promise<ILoadResult<T>> {
    try {
      return { value: await promise };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      return { value: fallback, error: `${label}: ${message}` };
    }
  }
}
