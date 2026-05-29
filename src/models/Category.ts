export interface Category {
  id: number;
  title: string;
  description: string;
  status: 'active' | 'inactive' | string;
  sortOrder?: number;
}
