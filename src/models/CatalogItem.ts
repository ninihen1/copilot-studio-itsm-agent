export interface CatalogItem {
  id: number;
  itemCode: string;
  itemName: string;
  category: string;
  description: string;
  status: 'active' | 'inactive' | 'deprecated';
  jobType?: string;
  cost?: number;
  slaDays?: number;
  visibility?: string;
  keywords?: string;
  inputSchema?: string;
  subcategoryHintId?: number;
  subcategoryHint?: string;
}
