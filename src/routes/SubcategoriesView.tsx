import * as React from 'react';
import { Subcategory } from '../models/Subcategory';

interface ISubcategoriesViewProps {
  subcategories: Subcategory[];
  isLoading: boolean;
}

export const SubcategoriesView: React.FC<ISubcategoriesViewProps> = ({ subcategories, isLoading }) => {
  const grouped = subcategories.reduce((groups, subcategory) => {
    const category = subcategory.category || 'Uncategorized';
    groups[category] = groups[category] || [];
    groups[category].push(subcategory);
    return groups;
  }, {} as Record<string, Subcategory[]>);

  const categories = Object.keys(grouped).sort((left, right) => left.localeCompare(right));

  return (
    <div className="itsm-view">
      <section className="hero-strip">
        <div className="hero-content">
          <div>
            <p className="eyebrow">Subcategories</p>
            <h1>Ticket routing taxonomy</h1>
            <p className="subtitle">Live SharePoint subcategories grouped by parent category, automation hint, and active state.</p>
          </div>
          <div className="commandbar">
            <button className="btn ghost-on-dark">Export</button>
            <button className="btn primary">Open taxonomy</button>
          </div>
        </div>
      </section>
      <section className="summary-strip">
        <article className="metric"><span>Active subcategories</span><strong>{isLoading ? '...' : subcategories.length}</strong></article>
        <article className="metric"><span>Categories</span><strong>{isLoading ? '...' : categories.length}</strong></article>
        <article className="metric"><span>Automated hints</span><strong>{isLoading ? '...' : subcategories.filter(item => !!item.jobTypeHint).length}</strong></article>
      </section>
      <section className="surface">
        <div className="surface-header">
          <h2 className="surface-title">Category map</h2>
          <input className="inline-search" placeholder="Search subcategories" />
        </div>
        <div className="surface-body">
          {isLoading && <ul className="ticket-list"><li><strong>Loading subcategories</strong><span>Reading the Subcategories list...</span></li></ul>}
          {!isLoading && categories.map(category => (
            <div key={category} className="taxonomy-group">
              <div className="taxonomy-heading">
                <h3>{category}</h3>
                <span className="status-pill neutral">{grouped[category].length} items</span>
              </div>
              <div className="taxonomy-grid">
                {grouped[category].map(subcategory => (
                  <article key={subcategory.id} className="catalog-card">
                    <span className={subcategory.jobTypeHint ? 'status-pill success' : 'status-pill neutral'}>{subcategory.jobTypeHint ? 'Automated' : 'Manual'}</span>
                    <strong>{subcategory.title}</strong>
                    <p>{subcategory.description || 'No description provided.'}</p>
                    <p>{subcategory.jobTypeHint || 'No job type hint'}</p>
                  </article>
                ))}
              </div>
            </div>
          ))}
          {!isLoading && subcategories.length === 0 && <ul className="ticket-list"><li><strong>No subcategories found</strong><span>Active subcategories will appear here.</span></li></ul>}
        </div>
      </section>
    </div>
  );
};
