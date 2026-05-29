import * as React from 'react';
import { CatalogItem } from '../models/CatalogItem';
import { LicenseCost } from '../models/LicenseCost';

interface ICatalogViewProps {
  items: CatalogItem[];
  licenseCosts: LicenseCost[];
  isLoading: boolean;
  onOpenItem: (item: CatalogItem) => void;
}

function findLicenseCost(item: CatalogItem, costs: LicenseCost[]): LicenseCost | undefined {
  const text = [item.itemName, item.description, item.keywords, item.inputSchema].filter(Boolean).join(' ').toLowerCase();
  return costs.find(cost =>
    !!cost.skuPartNumber &&
    (text.indexOf(cost.skuPartNumber.toLowerCase()) >= 0 || text.indexOf(cost.title.toLowerCase()) >= 0)
  );
}

function formatCost(cost?: LicenseCost): string {
  if (!cost) {
    return 'Cost unavailable';
  }

  const price = cost.negotiatedPriceMonthly ?? cost.listPriceMonthly;
  if (price === undefined || price === null) {
    return `${cost.skuPartNumber} · Price not set`;
  }

  return `${cost.skuPartNumber} · ${cost.currency || 'USD'} ${price.toFixed(2)} / ${cost.billingCycle || 'Monthly'}`;
}

export const CatalogView: React.FC<ICatalogViewProps> = ({ items, licenseCosts, isLoading, onOpenItem }) => (
  <div className="itsm-view">
    <section className="hero-strip"><div className="hero-content"><div><p className="eyebrow">Service catalog</p><h1>Order IT services</h1><p className="subtitle">Search approved catalog items with SLA, cost, and approval expectations.</p></div><div className="commandbar"><button className="btn ghost-on-dark">Filter</button><button className="btn primary">Request service</button></div></div></section>
    <section className="card-grid">
      {isLoading && <article className="catalog-card"><span>Loading</span><strong>Service catalog</strong><p>Reading SharePoint list...</p></article>}
      {!isLoading && items.map(item => {
        const cost = item.jobType?.indexOf('licensing.') === 0 ? findLicenseCost(item, licenseCosts) : undefined;
        return (
          <article
            key={item.id}
            className="catalog-card"
            role="button"
            tabIndex={0}
            onClick={() => onOpenItem(item)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' || e.key === ' ') {
                e.preventDefault();
                onOpenItem(item);
              }
            }}
            style={{ cursor: 'pointer' }}
          >
            <span className="status-pill success">{item.jobType ? 'Automated' : 'Manual'}</span>
            <strong>{item.itemName}</strong>
            <p>{item.description || `${item.category} · ${item.slaDays || 0} day SLA`}</p>
            {item.jobType?.indexOf('licensing.') === 0 && <p>{formatCost(cost)}</p>}
          </article>
        );
      })}
      {!isLoading && items.length === 0 && <article className="catalog-card"><span>No items</span><strong>Service Catalog is empty</strong><p>Active catalog items will appear here.</p></article>}
    </section>
  </div>
)