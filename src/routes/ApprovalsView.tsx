import * as React from 'react';
import { RequestItem } from '../models/RequestItem';

interface IApprovalsViewProps {
  approvals: RequestItem[];
  isLoading: boolean;
  onOpenApproval: (approval: RequestItem) => void;
}

export const ApprovalsView: React.FC<IApprovalsViewProps> = ({ approvals, isLoading, onOpenApproval }) => (
  <div className="itsm-view">
    <section className="hero-strip"><div className="hero-content"><div><p className="eyebrow">Approvals</p><h1>Review pending requests</h1><p className="subtitle">RITMs waiting on manager decision.</p></div><div className="commandbar"><button className="btn ghost-on-dark">Reject selected</button><button className="btn primary">Approve selected</button></div></div></section>
    <section className="surface"><div className="surface-header"><h2 className="surface-title">Approval queue</h2><span className="status-pill warning">{isLoading ? 'Loading' : `${approvals.length} pending`}</span></div><div className="surface-body"><ul className="ticket-list">{isLoading && <li><strong>Loading approvals</strong><span>Reading Request Items...</span></li>}{!isLoading && approvals.map(approval => <li key={approval.id}><button className="list-row-button" onClick={() => onOpenApproval(approval)}><strong>{approval.parentTicketId ? `Ticket #${approval.parentTicketId} · RITM #${approval.id}` : `RITM #${approval.id}`}</strong><span>{approval.requestedFor || 'Requested user'} · {approval.catalogItem || 'Request'} · {approval.ritmState}</span></button></li>)}{!isLoading && approvals.length === 0 && <li><strong>No pending approvals</strong><span>Approved and rejected RITMs are hidden from this queue.</span></li>}</ul></div></section>
  </div>
);
