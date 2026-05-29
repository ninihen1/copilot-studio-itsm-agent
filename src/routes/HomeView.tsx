import * as React from 'react';
import { Ticket } from '../models/Ticket';
import { DashboardMetrics } from '../services/TicketService';

interface IHomeViewProps {
  metrics?: DashboardMetrics;
  tickets: Ticket[];
  isLoading: boolean;
  error?: string;
  onOpenTicket: (ticket: Ticket) => void;
}

export const HomeView: React.FC<IHomeViewProps> = ({ metrics, tickets, isLoading, error, onOpenTicket }) => (
  <div className="itsm-view">
    <section className="hero-strip">
      <div className="hero-content">
        <div>
          <p className="eyebrow">Home</p>
          <h1>Good morning</h1>
          <p className="subtitle">Your tickets, approvals, knowledge suggestions, and service health in one SharePoint workspace.</p>
        </div>
        <div className="commandbar">
          <button className="btn ghost-on-dark">Search KB</button>
          <button className="btn primary">New ticket</button>
        </div>
      </div>
    </section>
    <section className="summary-strip">
      <article className="metric"><span>My open tickets</span><strong>{isLoading ? '...' : metrics?.myOpenTickets ?? 0}</strong></article>
      <article className="metric"><span>Pending actions</span><strong>{isLoading ? '...' : metrics?.pendingApprovals ?? 0}</strong></article>
      <article className="metric"><span>Service health</span><strong>{isLoading ? '...' : metrics?.serviceHealthAlerts ?? 0}</strong></article>
      <article className="metric"><span>KB suggestions</span><strong>{isLoading ? '...' : metrics?.kbSuggestions ?? 0}</strong></article>
    </section>
    <section className="work-grid">
      <article className="surface">
        <div className="surface-header"><h2 className="surface-title">Recent activity</h2><button className="btn">View all</button></div>
        <div className="surface-body">
          <ul className="timeline">
            {error && <li><strong>Partial SharePoint data warning</strong><span>{error}</span></li>}
            {tickets.slice(0, 5).map(ticket => (
              <li key={ticket.id}>
                <button className="list-row-button" onClick={() => onOpenTicket(ticket)}>
                  <strong>{ticket.title}</strong><span>{ticket.shortDescription} · {ticket.ticketState}</span>
                </button>
              </li>
            ))}
            {!isLoading && tickets.length === 0 && <li><strong>No recent tickets</strong><span>Your ticket activity will appear here.</span></li>}
          </ul>
        </div>
      </article>
      <aside className="side-stack">
        <div className="soft-panel"><h3>Service health</h3><p>One Microsoft 365 advisory is being monitored by the service desk.</p></div>
        <div className="soft-panel"><h3>Suggested knowledge</h3><p>Restore a deleted SharePoint file, Teams meeting recording delays, and license request guidance.</p></div>
      </aside>
    </section>
  </div>
);
