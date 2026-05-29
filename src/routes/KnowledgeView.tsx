import * as React from 'react';
import { KnowledgeArticle } from '../services/KnowledgeService';

interface IKnowledgeViewProps {
  articles: KnowledgeArticle[];
  isLoading: boolean;
}

export const KnowledgeView: React.FC<IKnowledgeViewProps> = ({ articles, isLoading }) => (
  <div className="itsm-view">
    <section className="hero-strip">
      <div className="hero-content">
        <div>
          <p className="eyebrow">Knowledge base</p>
          <h1>Self-service articles</h1>
          <p className="subtitle">Browse the latest published articles to resolve issues quickly.</p>
        </div>
        <div className="commandbar">
          <button className="btn ghost-on-dark">Filter</button>
          <button className="btn primary">New article</button>
        </div>
      </div>
    </section>
    <section className="surface">
      <div className="surface-header">
        <h2 className="surface-title">Published articles</h2>
        <input className="inline-search" placeholder="Search knowledge base" />
      </div>
      <div className="surface-body">
        <ul className="ticket-list">
          {isLoading && <li><strong>Loading articles</strong><span>Reading Knowledge Base...</span></li>}
          {!isLoading && articles.map(article =>
            <li key={article.id}>
              <strong>{article.title}</strong>
              <span>{article.articleNumber} · {article.category || 'General'} · {article.summary}</span>
              {article.body && (
                <div
                  className="article-body"
                  style={{ marginTop: 8, fontSize: 13, lineHeight: 1.5, color: '#323130' }}
                  dangerouslySetInnerHTML={{ __html: article.body }}
                />
              )}
            </li>
          )}
          {!isLoading && articles.length === 0 && <li><strong>No published articles</strong><span>Published KB articles will appear here.</span></li>}
        </ul>
      </div>
    </section>
  </div>
);
