import { Subcategory } from '../models/Subcategory';
import { ISharePointServiceContext, SharePointServiceBase } from './SharePointServiceBase';

interface IListResponse<T> {
  value: T[];
}

interface ISubcategoryListItem {
  Id: number;
  Title: string;
  Description?: string;
  ParentCategory?: unknown;
  SubcategoryStatus?: Subcategory['status'];
  JobTypeHint?: string;
  SortOrder?: number;
}

export class SubcategoryService extends SharePointServiceBase {
  public constructor(context: ISharePointServiceContext) {
    super(context);
  }

  public async getActiveSubcategories(): Promise<Subcategory[]> {
    const select = '$select=Id,Title,Description,ParentCategory/Title,SubcategoryStatus,JobTypeHint,SortOrder';
    const response = await this.get<IListResponse<ISubcategoryListItem>>(this.listItemsUrl('Subcategories', `?${select}&$expand=ParentCategory&$filter=SubcategoryStatus eq 'active'&$orderby=ParentCategory/Title asc,SortOrder asc,Title asc&$top=200`));

    return response.value.map(item => ({
      id: item.Id,
      title: item.Title,
      description: item.Description || '',
      category: this.lookupValue(item.ParentCategory) || 'Uncategorized',
      status: item.SubcategoryStatus || 'active',
      jobTypeHint: item.JobTypeHint,
      sortOrder: item.SortOrder
    }));
  }
}
