import * as React from 'react';
import { RequestItem } from '../models/RequestItem';

export type CloseDisposition = 'fulfilled' | 'declined';

interface IServiceDeskQueueViewProps {
  queue: RequestItem[];
  isLoading: boolean;
  busyRitmId?: number;
  onClose: (ritm: RequestItem, disposition: CloseDisposition, closeNotes: string) => void;
}

// The hand-off flow stores the triage intent as JSON in the Variables column (and appends the
// same blob to WorkNotes after "Details:"). Parse it so the card can show the ACTUAL request in
// clean fields instead of either a raw-JSON wall or nothing.
interface HandoffIntent {
  originalText?: string;
  targetUserUpn?: string;
  resourceName?: string;
  resourceType?: string;
  summary?: string;
  reason?: string;
}

function parseIntent(variables?: string): HandoffIntent {
  if (!variables) {
    return {};
  }
  try {
    return JSON.parse(variables) as HandoffIntent;
  } catch (e) {
    return {};
  }
}

// Fallback only: the human sentence WorkNotes carries before the raw "Details:" JSON blob.
function cleanNotes(notes?: string): string {
  if (!notes) {
    return '';
  }
  const cut = notes.indexOf('Details:');
  return (cut >= 0 ? notes.slice(0, cut) : notes).trim();
}

export const ServiceDeskQueueView: React.FC<IServiceDeskQueueViewProps> = ({ queue, isLoading, busyRitmId, onClose }) => {
  const [openId, setOpenId] = React.useState<number | undefined>(undefined);
  const [notes, setNotes] = React.useState<string>('');

  const toggle = (id: number): void => {
    setOpenId(prev => (prev === id ? undefined : id));
    setNotes('');
  };

  return (
    <div className="itsm-view">
      <section className="hero-strip">
        <div className="hero-content">
          <div>
            <p className="eyebrow">Service Desk</p>
            <h1>Hand-off fulfilment queue</h1>
            <p className="subtitle">Requests the automation could not fulfil, routed here for a human to action and close.</p>
          </div>
        </div>
      </section>
      <section className="surface">
        <div className="surface-header">
          <h2 className="surface-title">Open hand-offs</h2>
          <span className="status-pill warning">{isLoading ? 'Loading' : `${queue.length} open`}</span>
        </div>
        <div className="surface-body">
          <ul className="ticket-list">
            {isLoading && (
              <li><strong>Loading queue</strong><span>Reading hand-off Request Items...</span></li>
            )}
            {!isLoading && queue.length === 0 && (
              <li><strong>Queue is clear</strong><span>No hand-off requests are waiting for the service desk.</span></li>
            )}
            {!isLoading && queue.map(ritm => {
              const intent = parseIntent(ritm.variables);
              const requestText = intent.originalText || intent.resourceName || ritm.catalogItem || '';
              const forWhom = intent.targetUserUpn || ritm.requestedFor || '';
              const whyHandoff = intent.summary || intent.reason || cleanNotes(ritm.workNotes);
              const isOpen = openId === ritm.id;
              const busy = busyRitmId === ritm.id;
              return (
                <li key={ritm.id}>
                  <button className="list-row-button" onClick={() => toggle(ritm.id)}>
                    <strong>{ritm.parentTicketId ? `Ticket #${ritm.parentTicketId} · RITM #${ritm.id}` : `RITM #${ritm.id}`}</strong>
                    <span>{ritm.requestedFor || 'Requester'} &middot; {ritm.catalogItem || 'Request'}</span>
                  </button>
                  {isOpen && (
                    <div className="queue-actions">
                      {requestText && <p className="queue-worknotes"><strong>Request:</strong> {requestText}</p>}
                      {forWhom && <p className="queue-worknotes"><strong>For:</strong> {forWhom}</p>}
                      {whyHandoff && <p className="queue-worknotes"><strong>Why hand-off:</strong> {whyHandoff}</p>}
                      <textarea
                        className="queue-note"
                        placeholder="Close notes - what you did, or why it was declined"
                        value={notes}
                        onChange={e => setNotes(e.target.value)}
                        disabled={busy}
                        rows={3}
                      />
                      <div className="commandbar">
                        <button className="btn ghost" disabled={busy} onClick={() => onClose(ritm, 'declined', notes)}>Decline</button>
                        <button className="btn primary" disabled={busy} onClick={() => onClose(ritm, 'fulfilled', notes)}>{busy ? 'Closing…' : 'Mark fulfilled'}</button>
                      </div>
                    </div>
                  )}
                </li>
              );
            })}
          </ul>
        </div>
      </section>
    </div>
  );
};
