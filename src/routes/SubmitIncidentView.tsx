import * as React from 'react';
import { IBasePickerSuggestionsProps, IPersonaProps, NormalPeoplePicker } from '@fluentui/react';
import { CatalogItem } from '../models/CatalogItem';
import { Category } from '../models/Category';
import { Subcategory } from '../models/Subcategory';
import { CreateIncidentInput, PeoplePickerUser } from '../services/TicketService';

interface ISubmitIncidentViewProps {
  categories: Category[];
  catalogItems: CatalogItem[];
  subcategories: Subcategory[];
  isSubmitting: boolean;
  currentUserDisplayName: string;
  currentUserEmail: string;
  onResolvePeople: (query: string) => Promise<PeoplePickerUser[]>;
  onSubmit: (input: CreateIncidentInput) => Promise<void>;
}

interface ISubmitIncidentViewState {
  ticketType: CreateIncidentInput['ticketType'];
  shortDescription: string;
  description: string;
  categoryId: string;
  subcategoryId: string;
  catalogItemId: string;
  requestedForPeople: IPersonaProps[];
  typeOverrideConfirmed: boolean;
  impact: string;
  urgency: string;
  error?: string;
}

export class SubmitIncidentView extends React.Component<ISubmitIncidentViewProps, ISubmitIncidentViewState> {
  public constructor(props: ISubmitIncidentViewProps) {
    super(props);
    this.state = {
      ticketType: 'Incident',
      shortDescription: '',
      description: '',
      categoryId: '',
      subcategoryId: '',
      catalogItemId: '',
      requestedForPeople: [this.currentUserPersona(props)],
      typeOverrideConfirmed: false,
      impact: '2 - Medium',
      urgency: '2 - Medium'
    };
  }

  public componentDidMount(): void {
    if (!this.state.categoryId && this.props.categories.length > 0) {
      this.setState({ categoryId: String(this.props.categories[0].id) });
    }
  }

  public componentDidUpdate(previousProps: ISubmitIncidentViewProps): void {
    if (previousProps.categories !== this.props.categories && !this.state.categoryId && this.props.categories.length > 0) {
      this.setState({ categoryId: String(this.props.categories[0].id) });
    }
  }

  public render(): React.ReactElement {
    const filteredSubcategories = this.props.subcategories.filter(subcategory => subcategory.category === this.selectedCategoryTitle);
    const catalogMatches = this.catalogMatchesForSelectedSubcategory;
    const selectedSubcategory = this.selectedSubcategory;
    const shouldRecommendRequest = catalogMatches.length === 1 && this.state.ticketType === 'Incident';
    const requestNeedsCatalogChoice = this.state.ticketType === 'Request' && catalogMatches.length > 1;
    const requestHasNoCatalogMatch = this.state.ticketType === 'Request' && !!this.state.subcategoryId && catalogMatches.length === 0;

    return (
      <div className="itsm-view">
        <section className="hero-strip">
          <div className="hero-content">
            <div>
              <p className="eyebrow">Submit ticket</p>
              <h1>Create ticket</h1>
              <p className="subtitle">Search the knowledge base first, then send incident details to the triage automation.</p>
            </div>
            <div className="commandbar"><button className="btn ghost-on-dark">Search KB first</button><button className="btn primary" onClick={this.submit} disabled={this.props.isSubmitting}>Submit ticket</button></div>
          </div>
        </section>
        <section className="work-grid">
          <article className="surface">
            <div className="surface-header"><h2 className="surface-title">Ticket details</h2><span className="status-pill neutral">Draft</span></div>
            <div className="surface-body">
              <div className="form-section">
                <p className="section-label">Issue summary</p>
                <div className="form-grid">
                  <label className="field full">Title <span className="required">*</span><input value={this.state.shortDescription} onChange={event => this.setState({ shortDescription: event.currentTarget.value })} placeholder="Cannot access Teams recording after meeting" /></label>
                  <label className="field full">Description <span className="required">*</span><textarea value={this.state.description} onChange={event => this.setState({ description: event.currentTarget.value })} placeholder="Describe what happened, who is affected, and any error messages." /></label>
                </div>
              </div>
              <div className="form-section">
                <p className="section-label">Classification</p>
                <div className="form-grid">
                  <label className="field">Ticket type <span className="required">*</span>
                    <select value={this.state.ticketType} onChange={this.onTicketTypeChange}>
                      <option value="Incident">Incident</option>
                      <option value="Request">Request</option>
                    </select>
                  </label>
                  <label className="field">Category
                    <select value={this.state.categoryId} onChange={event => this.setState({ categoryId: event.currentTarget.value, subcategoryId: '' })}>
                      {this.props.categories.map(category => <option key={category.id} value={category.id}>{category.title}</option>)}
                    </select>
                  </label>
                  <label className="field">Subcategory
                    <select value={this.state.subcategoryId} onChange={this.onSubcategoryChange} disabled={!this.state.categoryId || filteredSubcategories.length === 0}>
                      <option value="">Select subcategory</option>
                      {filteredSubcategories.map(subcategory => <option key={subcategory.id} value={subcategory.id}>{subcategory.title}</option>)}
                    </select>
                  </label>
                  {this.state.ticketType === 'Request' && catalogMatches.length > 0 && (
                    <label className="field full">Catalog item <span className="required">*</span>
                      <select value={this.state.catalogItemId || (catalogMatches.length === 1 ? String(catalogMatches[0].id) : '')} onChange={event => this.setState({ catalogItemId: event.currentTarget.value })}>
                        {catalogMatches.length > 1 && <option value="">Select catalog item</option>}
                        {catalogMatches.map(item => <option key={item.id} value={item.id}>{item.itemName} ({item.itemCode})</option>)}
                      </select>
                    </label>
                  )}
                  {this.state.ticketType === 'Request' && (
                    <label className="field full request-for-field">Request for
                      <NormalPeoplePicker
                        selectedItems={this.state.requestedForPeople}
                        onResolveSuggestions={this.resolvePeople}
                        onChange={items => this.setState({ requestedForPeople: items || [] })}
                        getTextFromItem={item => item.text || item.secondaryText || ''}
                        pickerSuggestionsProps={this.peoplePickerSuggestions}
                        itemLimit={1}
                        inputProps={{ placeholder: this.props.currentUserEmail || this.props.currentUserDisplayName }}
                      />
                      <span className="help-text">Who is this request for? Leave blank if requesting for yourself.</span>
                    </label>
                  )}
                  <label className="field">Impact<select value={this.state.impact} onChange={event => this.setState({ impact: event.currentTarget.value })}><option>1 - High</option><option>2 - Medium</option><option>3 - Low</option></select></label>
                  <label className="field">Urgency<select value={this.state.urgency} onChange={event => this.setState({ urgency: event.currentTarget.value })}><option>1 - High</option><option>2 - Medium</option><option>3 - Low</option></select></label>
                </div>
                {shouldRecommendRequest && (
                  <div className="validation-callout warning">
                    <strong>Request recommended</strong>
                    <span>{selectedSubcategory?.title} maps to {catalogMatches[0].itemName}. Choose Request, or confirm this should stay an Incident.</span>
                    <label className="checkline"><input type="checkbox" checked={this.state.typeOverrideConfirmed} onChange={event => this.setState({ typeOverrideConfirmed: event.currentTarget.checked })} />Keep as Incident</label>
                  </div>
                )}
                {requestNeedsCatalogChoice && (
                  <div className="validation-callout warning">
                    <strong>Catalog item required</strong>
                    <span>Multiple active catalog items match this subcategory. Select the item that should drive fulfillment.</span>
                  </div>
                )}
                {requestHasNoCatalogMatch && (
                  <div className="validation-callout warning">
                    <strong>No catalog match</strong>
                    <span>This subcategory is not mapped to an active catalog item. Submit as an Incident for triage or choose a different subcategory.</span>
                  </div>
                )}
              </div>
              <div className="form-section">
                <p className="section-label">Attachments</p>
                <div className="dropzone"><div><strong>Drop files here</strong><span>Screenshots, logs, or related documents</span></div></div>
              </div>
              {this.state.error && <p className="form-error">{this.state.error}</p>}
            </div>
            <div className="form-footer"><button className="btn">Save draft</button><button className="btn primary" onClick={this.submit} disabled={this.props.isSubmitting}>{this.props.isSubmitting ? 'Submitting...' : 'Submit ticket'}</button></div>
          </article>
          <aside className="side-stack">
            <div className="soft-panel"><h3>Knowledge suggestions</h3><p>Run a KB search before submitting to surface possible fixes and deflection options.</p></div>
            <div className="soft-panel"><h3>Type validation</h3><p>{this.validationSummary}</p></div>
            <div className="soft-panel"><h3>SLA estimate</h3><p>Priority is calculated from impact and urgency after submission.</p></div>
          </aside>
        </section>
      </div>
    );
  }

  private get selectedCategoryTitle(): string | undefined {
    const selectedId = Number(this.state.categoryId);
    return this.props.categories.find(category => category.id === selectedId)?.title;
  }

  private get selectedSubcategory(): Subcategory | undefined {
    const selectedId = Number(this.state.subcategoryId);
    return this.props.subcategories.find(subcategory => subcategory.id === selectedId);
  }

  private get catalogMatchesForSelectedSubcategory(): CatalogItem[] {
    const selectedId = Number(this.state.subcategoryId);
    if (!selectedId) {
      return [];
    }
    return this.props.catalogItems.filter(item => item.subcategoryHintId === selectedId);
  }

  private get validationSummary(): string {
    if (!this.state.subcategoryId) {
      return 'Choose a subcategory to check whether it maps to an orderable service request.';
    }
    const matches = this.catalogMatchesForSelectedSubcategory;
    if (matches.length === 1) {
      return `This subcategory maps to ${matches[0].itemName}; Request is recommended.`;
    }
    if (matches.length > 1) {
      return 'This subcategory maps to multiple catalog items; Request submissions must pick the exact item.';
    }
    return 'No active catalog mapping exists; Incident is the default route.';
  }

  private onTicketTypeChange = (event: React.ChangeEvent<HTMLSelectElement>): void => {
    const ticketType = event.currentTarget.value as CreateIncidentInput['ticketType'];
    const catalogMatches = this.catalogMatchesForSelectedSubcategory;
    this.setState({
      ticketType,
      catalogItemId: ticketType === 'Request' && catalogMatches.length === 1 ? String(catalogMatches[0].id) : '',
      typeOverrideConfirmed: false,
      error: undefined
    });
  };

  private onSubcategoryChange = (event: React.ChangeEvent<HTMLSelectElement>): void => {
    const subcategoryId = event.currentTarget.value;
    const catalogMatches = this.props.catalogItems.filter(item => item.subcategoryHintId === Number(subcategoryId));
    this.setState({
      subcategoryId,
      catalogItemId: this.state.ticketType === 'Request' && catalogMatches.length === 1 ? String(catalogMatches[0].id) : '',
      typeOverrideConfirmed: false,
      error: undefined
    });
  };

  private submit = async (): Promise<void> => {
    if (!this.state.shortDescription.trim() || !this.state.description.trim() || !this.state.categoryId) {
      this.setState({ error: 'Title, description, and category are required.' });
      return;
    }
    const catalogMatches = this.catalogMatchesForSelectedSubcategory;
    if (this.state.ticketType === 'Request') {
      if (!this.state.subcategoryId) {
        this.setState({ error: 'Request tickets require a subcategory mapped to the service catalog.' });
        return;
      }
      if (catalogMatches.length === 0) {
        this.setState({ error: 'This subcategory has no active catalog item. Choose Incident or a mapped Request subcategory.' });
        return;
      }
      if (catalogMatches.length > 1 && !this.state.catalogItemId) {
        this.setState({ error: 'Select the catalog item for this Request.' });
        return;
      }
    }
    if (this.state.ticketType === 'Incident' && catalogMatches.length === 1 && !this.state.typeOverrideConfirmed) {
      this.setState({ error: 'This subcategory maps to a Request. Choose Request or confirm it should stay an Incident.' });
      return;
    }

    this.setState({ error: undefined });
    try {
      await this.props.onSubmit({
        ticketType: this.state.ticketType,
        shortDescription: this.state.shortDescription.trim(),
        description: this.state.description.trim(),
        categoryId: Number(this.state.categoryId),
        subcategoryId: this.state.subcategoryId ? Number(this.state.subcategoryId) : undefined,
        catalogItemId: this.state.catalogItemId ? Number(this.state.catalogItemId) : catalogMatches.length === 1 ? catalogMatches[0].id : undefined,
        requestedForUserLogin: this.requestedForLogin,
        typeOverrideConfirmed: this.state.typeOverrideConfirmed,
        impact: this.state.impact,
        urgency: this.state.urgency
      });
    } catch (error) {
      this.setState({ error: error instanceof Error ? error.message : 'Ticket submission failed.' });
    }
  };

  private get requestedForLogin(): string | undefined {
    const requestedFor = this.state.requestedForPeople[0];
    const login = typeof requestedFor?.key === 'string' ? requestedFor.key : requestedFor?.secondaryText;
    return login || undefined;
  }

  private readonly peoplePickerSuggestions: IBasePickerSuggestionsProps = {
    suggestionsHeaderText: 'Suggested people',
    noResultsFoundText: 'No people found',
    loadingText: 'Searching'
  };

  private currentUserPersona(props: ISubmitIncidentViewProps): IPersonaProps {
    return {
      key: props.currentUserEmail,
      text: props.currentUserDisplayName || props.currentUserEmail,
      secondaryText: props.currentUserEmail
    };
  }

  private resolvePeople = async (filterText: string, selectedItems?: IPersonaProps[]): Promise<IPersonaProps[]> => {
    const selectedKeys = (selectedItems || []).map(item => String(item.key || item.secondaryText || '').toLowerCase());
    const people = await this.props.onResolvePeople(filterText);
    return people
      .filter(person => selectedKeys.indexOf(person.loginName.toLowerCase()) === -1)
      .map(person => ({
        key: person.loginName,
        text: person.displayName,
        secondaryText: person.email || person.loginName
      }));
  };
}
