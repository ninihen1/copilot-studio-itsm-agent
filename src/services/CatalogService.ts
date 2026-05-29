import { CatalogItem } from '../models/CatalogItem';
import { ISharePointServiceContext, SharePointServiceBase } from './SharePointServiceBase';

interface IListResponse<T> {
  value: T[];
}

interface ICatalogListItem {
  Id: number;
  Title: string;
  ItemName?: string;
  Category?: unknown;
  Description?: string;
  ItemStatus?: CatalogItem['status'];
  JobType?: string;
  Cost?: number;
  SlaDays?: number;
  Visibility?: string;
  Keywords?: string;
  InputSchema?: string;
  SubcategoryHint?: { Id?: number; Title?: string };
}

export class CatalogService extends SharePointServiceBase {
  public constructor(context: ISharePointServiceContext) {
    super(context);
  }

  public async getActiveItems(): Promise<CatalogItem[]> {
    const select = '$select=Id,Title,ItemName,Category/Title,Description,ItemStatus,JobType,Cost,SlaDays,Visibility,Keywords,InputSchema,SubcategoryHint/Id,SubcategoryHint/Title';
    const response = await this.get<IListResponse<ICatalogListItem>>(this.listItemsUrl('Service Catalog', `?${select}&$expand=Category,SubcategoryHint&$filter=ItemStatus eq 'active'&$orderby=ItemName asc&$top=200`));

    return response.value.map(item => ({
      id: item.Id,
      itemCode: item.Title,
      itemName: item.ItemName || item.Title,
      category: this.lookupValue(item.Category) || '',
      description: item.Description || '',
      status: item.ItemStatus || 'active',
      jobType: item.JobType,
      cost: item.Cost,
      slaDays: item.SlaDays,
      visibility: item.Visibility,
      keywords: item.Keywords,
      inputSchema: item.InputSchema,
      subcategoryHintId: item.SubcategoryHint?.Id,
      subcategoryHint: item.SubcategoryHint?.Title
    }));
  }
}
