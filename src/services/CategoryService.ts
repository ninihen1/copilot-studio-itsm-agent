import { Category } from '../models/Category';
import { ISharePointServiceContext, SharePointServiceBase } from './SharePointServiceBase';

interface IListResponse<T> {
  value: T[];
}

interface ICategoryListItem {
  Id: number;
  Title: string;
  Description?: string;
  Status?: Category['status'];
  SortOrder?: number;
}

export class CategoryService extends SharePointServiceBase {
  public constructor(context: ISharePointServiceContext) {
    super(context);
  }

  public async getActiveCategories(): Promise<Category[]> {
    const select = '$select=Id,Title,Description,Status,SortOrder';
    const response = await this.get<IListResponse<ICategoryListItem>>(this.listItemsUrl('Categories', `?${select}&$filter=Status eq 'active'&$orderby=SortOrder asc,Title asc&$top=200`));

    return response.value.map(item => ({
      id: item.Id,
      title: item.Title,
      description: item.Description || '',
      status: item.Status || 'active',
      sortOrder: item.SortOrder
    }));
  }
}
