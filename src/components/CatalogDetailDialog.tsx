import * as React from 'react';
import { Dialog, DialogType, DialogFooter, PrimaryButton } from '@fluentui/react';
import { CatalogItem } from '../models/CatalogItem';

export interface ICatalogDetailDialogProps {
  isOpen: boolean;
  item?: CatalogItem;
  onDismiss: () => void;
}

function formatStatus(status: CatalogItem['status']): string {
  if (status === 'active') { return 'Active'; }
  if (status === 'inactive') { return 'Inactive'; }
  return 'Deprecated';
}

function formatCost(cost?: number): string {
  if (cost === undefined || cost === null) { return '—'; }
  return `$${cost.toFixed(2)}`;
}

function formatField(value: string | number | undefined): string {
  if (value === undefined || value === null || value === '') { return '—'; }
  return String(value);
}

export const CatalogDetailDialog: React.FC<ICatalogDetailDialogProps> = ({ isOpen, item, onDismiss }) => {
  if (!item) {
    return null;
  }

  return (
    <Dialog
      hidden={!isOpen}
      onDismiss={onDismiss}
      dialogContentProps={{
        type: DialogType.largeHeader,
        title: item.itemName,
        subText: `${item.itemCode} · ${item.category}`
      }}
      modalProps={{
        isBlocking: false,
        containerClassName: 'detail-dialog'
      }}
      minWidth={760}
      maxWidth={980}
    >
      <div className="detail-section">
        <h3>Overview</h3>
        <div className="detail-field-grid">
          <div><strong>Status</strong><div>{formatStatus(item.status)}</div></div>
          <div><strong>Category</strong><div>{formatField(item.category)}</div></div>
          <div><strong>Subcategory</strong><div>{formatField(item.subcategoryHint)}</div></div>
          <div><strong>Job type</strong><div>{formatField(item.jobType)}</div></div>
          <div><strong>Cost</strong><div>{formatCost(item.cost)}</div></div>
          <div><strong>SLA</strong><div>{item.slaDays !== undefined ? `${item.slaDays} day(s)` : '—'}</div></div>
          <div><strong>Visibility</strong><div>{formatField(item.visibility)}</div></div>
          <div><strong>Item code</strong><div>{formatField(item.itemCode)}</div></div>
        </div>
      </div>

      {item.description && (
        <div className="detail-section">
          <h3>Description</h3>
          <p>{item.description}</p>
        </div>
      )}

      {item.keywords && (
        <div className="detail-section">
          <h3>Keywords</h3>
          <p>{item.keywords}</p>
        </div>
      )}

      {item.inputSchema && (
        <div className="detail-section">
          <h3>Input schema</h3>
          <pre style={{ whiteSpace: 'pre-wrap', fontFamily: 'Consolas, monospace', fontSize: 12 }}>{item.inputSchema}</pre>
        </div>
      )}

      <DialogFooter>
        <PrimaryButton onClick={onDismiss} text="Close" />
      </DialogFooter>
    </Dialog>
  );
}
