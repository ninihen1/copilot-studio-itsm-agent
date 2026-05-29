import * as React from 'react';
import { Ticket } from '../models/Ticket';

interface ITicketDetailViewProps {
  tickets: Ticket[];
  isLoading: boolean;
  onOpenTicket: (ticket: Ticket) => void;
}

export const TicketDetailView: React.FC<ITicketDetailViewProps> = ({ tickets, isLoading, onOpenTicket }) => {
  const selectedTicket = tickets[0];
  return (
  <div className="itsm-view">
    <section className="hero-strip"><div className="hero-content"><div><p className="eyebrow">My tickets</p><h1>{selectedTicket ? selectedTicket.title : 'Ticket status'}</h1><p className="subtitle">{selectedTicket ? `${selectedTicket.ticketState} · ${selectedTicket.slaStatus || 'SLA pending'} · ${selectedTicket.priority || 'Priority pending'}` : 'Recent SharePoint ticket activity'}</p></div><div className="commandbar"><button className="btn ghost-on-dark">Add comment</button><button className="btn primary">Follow</button></div></div></section>
    <section className="work-grid">
      <article className="surface"><div className="surface-header"><h2 className="surface-title">Recent tickets</h2><span className="status-pill success">{tickets.length} loaded</span></div><div className="surface-body"><ul className="ticket-list">{isLoading && <li><strong>Loading tickets</strong><span>Reading the Tickets list...</span></li>}{!isLoading && tickets.map(ticket => <li key={ticket.id}><button className="list-row-button" onClick={() => onOpenTicket(ticket)}><strong>{ticket.title}</strong><span>{ticket.shortDescription} · {ticket.ticketState} · {ticket.category || 'Uncategorized'}</span></button></li>)}{!isLoading && tickets.length === 0 && <li><strong>No tickets found</strong><span>Your tickets will appear here.</span></li>}</ul></div></article>
      <aside className="side-stack"><div className="soft-panel"><h3>Summary</h3><p>{selectedTicket ? `${selectedTicket.ticketType} opened ${selectedTicket.created || 'recently'}.` : 'Select a ticket to review details.'}</p></div><div className="soft-panel"><h3>Automation</h3><p>Provisioning job history will appear as ticket detail wiring expands.</p></div></aside>
    </section>
  </div>
  );
};
