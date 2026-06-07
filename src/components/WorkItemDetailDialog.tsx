import * as React from 'react';
import { DefaultButton, Dialog, DialogFooter, DialogType, PrimaryButton, TextField } from '@fluentui/react';
import { ProvisioningJob } from '../models/ProvisioningJob';
import { RequestItem } from '../models/RequestItem';
import { Task } from '../models/Task';
import { Ticket } from '../models/Ticket';

export type WorkItemDetailKind = 'ticket' | 'approval' | 'job';

export interface WorkItemDetailDialogProps {
  isOpen: boolean;
  isLoading: boolean;
  error?: string;
  kind?: WorkItemDetailKind;
  ticket?: Ticket;
  requestItem?: RequestItem;
  job?: ProvisioningJob;
  requestItems: RequestItem[];
  jobs: ProvisioningJob[];
  tasks: Task[];
  onDismiss: () => void;
  onAddTicketComment: (ticket: Ticket, comment: string) => Promise<void>;
  onToggleTicketFollow: (ticket: Ticket) => Promise<void>;
  onEscalateTicket: (ticket: Ticket) => Promise<void>;
  onApproveRequest: (requestItem: RequestItem, comment?: string) => Promise<void>;
  onRejectRequest: (requestItem: RequestItem, comment?: string) => Promise<void>;
  onAddApprovalComment: (requestItem: RequestItem, comment: string) => Promise<void>;
  onRetryJob: (job: ProvisioningJob) => Promise<void>;
  onCancelJob: (job: ProvisioningJob) => Promise<void>;
}

interface TimelineStep {
  label: string;
  detail: string;
  state: 'completed' | 'current' | 'pending';
}

export const WorkItemDetailDialog: React.FC<WorkItemDetailDialogProps> = props => {
  const title = dialogTitle(props);
  const timeline = buildTimeline(props);
  const [prompt, setPrompt] = React.useState<{ title: string; label: string; required?: boolean; onSave: (value: string) => Promise<void> } | undefined>();
  const [promptValue, setPromptValue] = React.useState('');
  const [actionStatus, setActionStatus] = React.useState<string | undefined>();
  const [actionError, setActionError] = React.useState<string | undefined>();
  const [isActionBusy, setIsActionBusy] = React.useState(false);

  React.useEffect(() => {
    if (!props.isOpen) {
      setPrompt(undefined);
      setPromptValue('');
      setActionStatus(undefined);
      setActionError(undefined);
      setIsActionBusy(false);
    }
  }, [props.isOpen]);

  const runAction = async (label: string, action: () => Promise<void>): Promise<void> => {
    setIsActionBusy(true);
    setActionError(undefined);
    setActionStatus(undefined);
    try {
      await action();
      setActionStatus(label);
      setPrompt(undefined);
      setPromptValue('');
    } catch (error) {
      setActionError(error instanceof Error ? error.message : 'Action failed.');
    } finally {
      setIsActionBusy(false);
    }
  };

  return (
    <>
      <Dialog
        hidden={!props.isOpen}
        onDismiss={props.onDismiss}
        dialogContentProps={{
          type: DialogType.largeHeader,
          title,
          subText: props.error || statusSubtitle(props)
        }}
        modalProps={{
          isBlocking: false,
          containerClassName: 'detail-dialog'
        }}
        minWidth={760}
        maxWidth={980}
      >
        {props.isLoading ? (
          <div className="detail-loading">Loading related workflow details...</div>
        ) : (
          <div className="detail-dialog-body">
            {(actionStatus || actionError) && (
              <div className={actionError ? 'detail-action-error' : 'detail-action-status'}>
                {actionError || actionStatus}
              </div>
            )}
            <section className="detail-status-row">
              {statusBadges(props).map(badge => <span key={badge.label} className={`status-pill ${badge.tone}`}>{badge.label}: {badge.value}</span>)}
            </section>

            <section className="detail-section">
              <h3>Request inputs</h3>
              <div className="detail-field-grid">
                {inputFields(props).map(field => (
                  <div className="detail-field" key={field.label}>
                    <span>{field.label}</span>
                    <strong>{field.value || 'Not set'}</strong>
                  </div>
                ))}
              </div>
              {longFormInput(props) && <pre className="detail-json">{longFormInput(props)}</pre>}
            </section>

            <section className="detail-section">
              <h3>Workflow progress</h3>
              <ol className="workflow-timeline">
                {timeline.map(step => (
                  <li key={step.label} className={step.state}>
                    <span className="timeline-dot" />
                    <div>
                      <strong>{step.label}</strong>
                      <span>{step.detail}</span>
                    </div>
                  </li>
                ))}
              </ol>
            </section>

            <section className="detail-section">
              <h3>Related items</h3>
              {renderRelatedItems(props)}
            </section>

            <section className="detail-section">
              <h3>Available actions</h3>
              <div className="detail-actions">
                {actionButtons(props, isActionBusy, runAction, setPrompt)}
              </div>
            </section>
          </div>
        )}
        <DialogFooter>
          <DefaultButton onClick={props.onDismiss} text="Close" disabled={isActionBusy} />
        </DialogFooter>
      </Dialog>
      <Dialog
        hidden={!prompt}
        onDismiss={() => !isActionBusy && setPrompt(undefined)}
        dialogContentProps={{
          type: DialogType.normal,
          title: prompt?.title || ''
        }}
        modalProps={{ isBlocking: isActionBusy }}
      >
        <TextField
          label={prompt?.label}
          multiline
          rows={4}
          value={promptValue}
          onChange={(_, value) => setPromptValue(value || '')}
          disabled={isActionBusy}
        />
        <DialogFooter>
          <PrimaryButton
            text={isActionBusy ? 'Saving...' : 'Save'}
            disabled={isActionBusy || (!!prompt?.required && !promptValue.trim())}
            onClick={() => prompt && runAction('Action saved.', () => prompt.onSave(promptValue.trim()))}
          />
          <DefaultButton text="Cancel" onClick={() => setPrompt(undefined)} disabled={isActionBusy} />
        </DialogFooter>
      </Dialog>
    </>
  );
};

function dialogTitle(props: WorkItemDetailDialogProps): string {
  if (props.kind === 'approval') {
    const r = props.requestItem;
    if (!r) {
      return 'Approval detail';
    }
    return r.parentTicketId ? `Ticket #${r.parentTicketId} · RITM #${r.id}` : `RITM #${r.id}`;
  }
  if (props.kind === 'job') {
    return props.job ? `Provisioning job ${props.job.jobId}` : 'Provisioning job detail';
  }
  return props.ticket ? `Ticket #${props.ticket.id}` : 'Ticket detail';
}

function statusSubtitle(props: WorkItemDetailDialogProps): string {
  if (props.kind === 'approval' && props.requestItem) {
    return `${props.requestItem.ritmState} for ${props.requestItem.requestedFor || 'requested user'}`;
  }
  if (props.kind === 'job' && props.job) {
    return `${props.job.jobStatus} · ${props.job.jobType || 'No job type'}`;
  }
  if (props.ticket) {
    return `${props.ticket.ticketType} · ${props.ticket.ticketState}`;
  }
  return 'Workflow details';
}

function statusBadges(props: WorkItemDetailDialogProps): Array<{ label: string; value: string; tone: string }> {
  const ticket = props.ticket;
  const request = props.requestItem;
  const job = props.job;
  return [
    { label: 'Status', value: job?.jobStatus || request?.ritmState || ticket?.ticketState || 'Unknown', tone: 'success' },
    { label: 'Opened', value: formatDate(job?.created || request?.created || ticket?.created), tone: 'neutral' },
    { label: 'Updated', value: formatDate(job?.modified || request?.modified || ticket?.modified), tone: 'warning' }
  ];
}

function inputFields(props: WorkItemDetailDialogProps): Array<{ label: string; value?: string }> {
  if (props.kind === 'job' && props.job) {
    return [
      { label: 'Job ID', value: props.job.jobId },
      { label: 'Job type', value: props.job.jobType },
      { label: 'Caller', value: props.job.callerUpn },
      { label: 'Parent ticket ID', value: String(props.job.parentTicketId || '') },
      { label: 'Parent RITM ID', value: props.job.parentRitmId ? String(props.job.parentRitmId) : undefined },
      { label: 'Correlation ID', value: props.job.correlationId },
      { label: 'Service principal', value: props.job.servicePrincipal },
      { label: 'Graph request ID', value: props.job.graphRequestId }
    ];
  }

  if (props.kind === 'approval' && props.requestItem) {
    return [
      { label: 'RITM', value: props.requestItem.ritmNumber },
      { label: 'Catalog item', value: props.requestItem.catalogItem || String(props.requestItem.catalogItemId || '') },
      { label: 'Requested for', value: props.requestItem.requestedFor },
      { label: 'Parent ticket ID', value: String(props.requestItem.parentTicketId || '') },
      { label: 'Approval state', value: props.requestItem.ritmState }
    ];
  }

  const ticket = props.ticket;
  return [
    { label: 'Ticket number', value: ticket?.title },
    { label: 'Type', value: ticket?.ticketType },
    { label: 'State', value: ticket?.ticketState },
    { label: 'Caller', value: ticket?.caller },
    { label: 'Source', value: ticket?.ticketSource },
    { label: 'Category', value: ticket?.category },
    { label: 'Subcategory', value: ticket?.subcategory },
    { label: 'Impact', value: ticket?.impact },
    { label: 'Urgency', value: ticket?.urgency },
    { label: 'Priority', value: ticket?.priority },
    { label: 'Close code', value: ticket?.closeCode },
    { label: 'Closed', value: formatDate(ticket?.closedDate) },
    { label: 'Confidentiality', value: ticket?.confidentialityLevel },
    { label: 'Type validation', value: ticket?.ticketTypeValidationStatus },
    { label: 'Suggested type', value: ticket?.suggestedTicketType }
  ];
}

function longFormInput(props: WorkItemDetailDialogProps): string | undefined {
  if (props.kind === 'job' && props.job) {
    return [
      props.job.targetJson ? `Target\n${formatJson(props.job.targetJson)}` : '',
      props.job.argsJson ? `Arguments\n${formatJson(props.job.argsJson)}` : '',
      props.job.errorJson ? `Error\n${formatJson(props.job.errorJson)}` : ''
    ].filter(Boolean).join('\n\n');
  }

  if (props.kind === 'approval' && props.requestItem?.variables) {
    return formatJson(props.requestItem.variables);
  }

  const parts = [
    props.ticket?.shortDescription ? `Summary\n${props.ticket.shortDescription}` : '',
    props.ticket?.description ? `Description\n${props.ticket.description}` : '',
    props.ticket?.closeNotes ? `Close notes\n${props.ticket.closeNotes}` : '',
    props.ticket?.workNotes ? `Work notes\n${props.ticket.workNotes}` : '',
    props.ticket?.ticketTypeValidationReason ? `Validation reason\n${props.ticket.ticketTypeValidationReason}` : ''
  ].filter(Boolean);
  return parts.length ? parts.join('\n\n') : undefined;
}

function buildTimeline(props: WorkItemDetailDialogProps): TimelineStep[] {
  if (props.kind === 'job' && props.job) {
    const order = ['Proposed', 'AwaitingApproval', 'Dispatched', 'InProgress', 'Succeeded'];
    return statusTimeline(order, props.job.jobStatus, {
      Proposed: 'Job proposal captured',
      AwaitingApproval: 'Approval gate active',
      Dispatched: 'Dispatcher accepted work',
      InProgress: 'Executor running',
      Succeeded: 'Executor completed'
    });
  }

  if (props.kind === 'approval' && props.requestItem) {
    return statusTimeline(['Pending Approval', 'Approved', 'In Progress', 'Closed Complete'], props.requestItem.ritmState, {
      'Pending Approval': 'Waiting for approver decision',
      Approved: 'Approval granted',
      'In Progress': 'Catalog tasks running',
      'Closed Complete': 'Request item fulfilled'
    });
  }

  const validationDone = props.ticket?.ticketTypeValidated || props.ticket?.ticketTypeValidationStatus === 'Validated' || props.ticket?.ticketTypeValidationStatus === 'Reclassified';
  return [
    { label: 'Submitted', detail: formatDate(props.ticket?.created), state: 'completed' },
    { label: 'Type validation', detail: props.ticket?.ticketTypeValidationStatus || 'Pending', state: validationDone ? 'completed' : 'current' },
    { label: props.ticket?.ticketType === 'Request' ? 'RITM generation' : 'Triage', detail: props.requestItems.length || props.jobs.length ? 'Related workflow created' : 'Waiting for automation', state: validationDone ? (props.requestItems.length || props.jobs.length ? 'completed' : 'current') : 'pending' },
    { label: 'Fulfillment', detail: props.jobs.length ? `${props.jobs.length} provisioning job(s)` : 'No provisioning jobs yet', state: props.jobs.some(job => job.jobStatus === 'Succeeded') ? 'completed' : props.jobs.length ? 'current' : 'pending' },
    { label: 'Resolution', detail: props.ticket?.ticketState || 'Pending', state: ['Resolved', 'Closed', 'Cancelled'].indexOf(props.ticket?.ticketState || '') >= 0 ? 'completed' : 'pending' }
  ];
}

function statusTimeline(order: string[], current: string, details: Record<string, string>): TimelineStep[] {
  const currentIndex = Math.max(order.indexOf(current), 0);
  return order.map((label, index) => ({
    label,
    detail: details[label] || label,
    state: index < currentIndex ? 'completed' : index === currentIndex ? 'current' : 'pending'
  }));
}

function renderRelatedItems(props: WorkItemDetailDialogProps): React.ReactElement {
  const hasRelated = !!props.ticket || props.requestItems.length > 0 || props.jobs.length > 0 || props.tasks.length > 0 || !!props.requestItem;
  if (!hasRelated) {
    return <p className="detail-empty">No related workflow records loaded.</p>;
  }

  return (
    <div className="related-tree">
      {props.ticket && <div className="related-row"><strong>Ticket #{props.ticket.id}</strong><span>{props.ticket.ticketType} · {props.ticket.ticketState}</span></div>}
      {props.requestItems.map(item => <div className="related-row child" key={`ritm-${item.id}`}><strong>RITM #{item.id}</strong><span>{item.catalogItem || 'Catalog item'} · {item.ritmState}</span></div>)}
      {props.requestItem && !props.requestItems.some(item => item.id === props.requestItem?.id) && <div className="related-row child"><strong>RITM #{props.requestItem.id}</strong><span>Approval · {props.requestItem.ritmState}</span></div>}
      {props.tasks.map(task => <div className="related-row grandchild" key={`task-${task.id}`}><strong>{task.taskNumber}</strong><span>{task.shortDescription || 'Catalog task'} · {task.taskState}</span></div>)}
      {props.jobs.map(job => <div className="related-row grandchild" key={`job-${job.id}`}><strong>{job.jobId}</strong><span>{job.jobType} · {job.jobStatus}</span></div>)}
    </div>
  );
}

function actionButtons(
  props: WorkItemDetailDialogProps,
  isBusy: boolean,
  runAction: (label: string, action: () => Promise<void>) => Promise<void>,
  setPrompt: (prompt: { title: string; label: string; required?: boolean; onSave: (value: string) => Promise<void> }) => void
): React.ReactElement[] {
  if (props.kind === 'approval') {
    return [
      <PrimaryButton key="approve" text="Approve" disabled={isBusy || props.requestItem?.ritmState !== 'Pending Approval'} onClick={() => props.requestItem && runAction('Request approved.', () => props.onApproveRequest(props.requestItem as RequestItem))} />,
      <DefaultButton key="reject" text="Reject" disabled={isBusy || props.requestItem?.ritmState !== 'Pending Approval'} onClick={() => props.requestItem && setPrompt({ title: 'Reject request', label: 'Reason', required: true, onSave: value => props.onRejectRequest(props.requestItem as RequestItem, value) })} />,
      <DefaultButton key="comment" text="Add comment" disabled={isBusy || !props.requestItem} onClick={() => props.requestItem && setPrompt({ title: 'Approval comment', label: 'Comment', required: true, onSave: value => props.onAddApprovalComment(props.requestItem as RequestItem, value) })} />
    ];
  }

  if (props.kind === 'job') {
    return [
      <PrimaryButton key="retry" text="Retry job" disabled={isBusy || props.job?.jobStatus !== 'Failed'} onClick={() => props.job && runAction('Job queued for retry.', () => props.onRetryJob(props.job as ProvisioningJob))} />,
      <DefaultButton key="copy" text="Copy correlation" disabled={isBusy || !props.job?.correlationId} onClick={() => {
        const correlationId = props.job?.correlationId;
        if (!correlationId) {
          return;
        }
        runAction('Correlation copied.', async () => {
        if (!navigator.clipboard) {
          throw new Error('Clipboard API is not available.');
        }
        await navigator.clipboard.writeText(correlationId);
        });
      }} />,
      <DefaultButton key="cancel" text="Cancel" disabled={isBusy || props.job?.jobStatus === 'Succeeded' || props.job?.jobStatus === 'Cancelled'} onClick={() => props.job && runAction('Job cancelled.', () => props.onCancelJob(props.job as ProvisioningJob))} />
    ];
  }

  return [
    <PrimaryButton key="comment" text="Add comment" disabled={isBusy || !props.ticket} onClick={() => props.ticket && setPrompt({ title: 'Add ticket comment', label: 'Comment', required: true, onSave: value => props.onAddTicketComment(props.ticket as Ticket, value) })} />,
    <DefaultButton key="follow" text="Follow" disabled={isBusy || !props.ticket} onClick={() => props.ticket && runAction('Follow subscription updated.', () => props.onToggleTicketFollow(props.ticket as Ticket))} />,
    <DefaultButton key="escalate" text="Escalate" disabled={isBusy || props.ticket?.ticketState === 'Closed' || props.ticket?.escalationFlag} onClick={() => props.ticket && runAction('Ticket escalated.', () => props.onEscalateTicket(props.ticket as Ticket))} />
  ];
}

function formatDate(value?: string): string {
  if (!value) {
    return 'Not stamped';
  }
  return new Date(value).toLocaleString();
}

function formatJson(value: string): string {
  try {
    return JSON.stringify(JSON.parse(value), null, 2);
  } catch {
    return value;
  }
}
