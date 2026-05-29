import * as React from 'react';
import { LicenseCost } from '../models/LicenseCost';
import { ProvisioningJob } from '../models/ProvisioningJob';
import { DashboardMetrics } from '../services/TicketService';

interface IAdminViewProps {
  metrics?: DashboardMetrics;
  failedJobs: ProvisioningJob[];
  licenseCosts: LicenseCost[];
  licenseCostCount: number;
  isLoading: boolean;
  onOpenJob: (job: ProvisioningJob) => void;
}

function formatMoney(cost: LicenseCost): string {
  const price = cost.negotiatedPriceMonthly ?? cost.listPriceMonthly;
  if (price === undefined || price === null) {
    return 'No price';
  }

  return `${cost.currency || 'USD'} ${price.toFixed(2)} / ${cost.billingCycle || 'Monthly'}`;
}

export const AdminView: React.FC<IAdminViewProps> = ({ metrics, failedJobs, licenseCosts, licenseCostCount, isLoading, onOpenJob }) => (
  <div className="itsm-view">
    <section className="hero-strip"><div className="hero-content"><div><p className="eyebrow">Admin console</p><h1>Service desk operations</h1><p className="subtitle">Ticket queues, SLA warnings, failed jobs, and major incidents.</p></div><div className="commandbar"><button className="btn ghost-on-dark">Export</button><button className="btn primary">Open queue</button></div></div></section>
    <section className="summary-strip"><article className="metric"><span>Open tickets</span><strong>{isLoading ? '...' : metrics?.myOpenTickets ?? 0}</strong></article><article className="metric"><span>Pending approvals</span><strong>{isLoading ? '...' : metrics?.pendingApprovals ?? 0}</strong></article><article className="metric"><span>Failed PJs</span><strong>{isLoading ? '...' : failedJobs.length}</strong></article><article className="metric"><span>License SKUs</span><strong>{isLoading ? '...' : licenseCostCount}</strong></article></section>
    <section className="surface"><div className="surface-header"><h2 className="surface-title">Failed provisioning jobs</h2><span className="status-pill warning">{failedJobs.length} failed</span></div><div className="surface-body"><ul className="ticket-list">{isLoading && <li><strong>Loading jobs</strong><span>Reading Provisioning Jobs...</span></li>}{!isLoading && failedJobs.map(job => <li key={job.id}><button className="list-row-button" onClick={() => onOpenJob(job)}><strong>{job.jobId}</strong><span>{job.jobType} · {job.callerUpn} · {job.errorJson || 'No error details'}</span></button></li>)}{!isLoading && failedJobs.length === 0 && <li><strong>No failed jobs</strong><span>Provisioning job failures will appear here.</span></li>}</ul></div></section>
    <section className="surface"><div className="surface-header"><h2 className="surface-title">License Costs</h2><span className="status-pill success">{licenseCostCount} SKUs</span></div><div className="surface-body"><ul className="ticket-list">{isLoading && <li><strong>Loading license costs</strong><span>Reading License Costs...</span></li>}{!isLoading && licenseCosts.map(cost => <li key={cost.id}><strong>{cost.officialProductName || cost.title}</strong><span>{cost.skuPartNumber || 'No SKU'} · {formatMoney(cost)} · Verified {cost.lastVerified ? new Date(cost.lastVerified).toLocaleDateString() : 'unknown'}</span></li>)}{!isLoading && licenseCosts.length === 0 && <li><strong>No license costs found</strong><span>License Costs rows will appear here after sync.</span></li>}</ul></div></section>
  </div>
);
