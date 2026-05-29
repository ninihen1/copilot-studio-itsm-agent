export interface Subcategory {
  id: number;
  title: string;
  description: string;
  category: string;
  status: 'active' | 'inactive' | string;
  jobTypeHint?: string;
  sortOrder?: number;
}
