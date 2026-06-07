import { LicenseCost } from '../models/LicenseCost';
import { ISharePointServiceContext, SharePointServiceBase } from './SharePointServiceBase';

interface IListResponse<T> {
  value: T[];
}

interface ILicenseCostListItem {
  Id: number;
  Title: string;
  SkuPartNumber?: string;
  SkuId?: string;
  Owned?: boolean;
  OfficialProductName?: string;
  ListPriceMonthly?: number;
  NegotiatedPriceMonthly?: number;
  Currency?: string;
  BillingCycle?: string;
  LastVerified?: string;
  SourceUrl?: string;
  Notes?: string;
}

export class LicenseCostService extends SharePointServiceBase {
  public constructor(context: ISharePointServiceContext) {
    super(context);
  }

  public async getRecentCosts(top: number = 25): Promise<LicenseCost[]> {
    const select = '$select=Id,Title,SkuPartNumber,SkuId,OfficialProductName,ListPriceMonthly,NegotiatedPriceMonthly,Currency,BillingCycle,LastVerified,SourceUrl,Notes';
    const response = await this.get<IListResponse<ILicenseCostListItem>>(this.listItemsUrl('License Costs', `?${select}&$orderby=LastVerified desc,Title asc&$top=${top}`));

    return response.value.map(item => this.mapLicenseCost(item));
  }

  public async getCostCount(): Promise<number> {
    const response = await this.get<IListResponse<{ Id: number }>>(this.listItemsUrl('License Costs', '?$select=Id&$top=5000'));
    return response.value.length;
  }

  public async getForPicker(): Promise<LicenseCost[]> {
    const select = '$select=Id,Title,SkuPartNumber,SkuId,Owned';
    const filter = '$filter=Owned eq 1';
    const response = await this.get<IListResponse<ILicenseCostListItem>>(this.listItemsUrl('License Costs', `?${select}&${filter}&$orderby=Title asc&$top=2000`));
    return response.value.filter(item => !!item.SkuPartNumber).map(item => this.mapLicenseCost(item));
  }

  public findBestMatch(costs: LicenseCost[], value?: string): LicenseCost | undefined {
    if (!value) {
      return undefined;
    }

    const normalized = value.toLowerCase();
    return costs.find(cost =>
      cost.skuPartNumber.toLowerCase() === normalized ||
      cost.title.toLowerCase().indexOf(normalized) >= 0 ||
      normalized.indexOf(cost.skuPartNumber.toLowerCase()) >= 0 ||
      normalized.indexOf(cost.title.toLowerCase()) >= 0
    );
  }

  private mapLicenseCost(item: ILicenseCostListItem): LicenseCost {
    return {
      id: item.Id,
      title: item.Title,
      skuPartNumber: item.SkuPartNumber || '',
      skuId: item.SkuId,
      owned: item.Owned,
      officialProductName: item.OfficialProductName,
      listPriceMonthly: item.ListPriceMonthly,
      negotiatedPriceMonthly: item.NegotiatedPriceMonthly,
      currency: item.Currency,
      billingCycle: item.BillingCycle,
      lastVerified: item.LastVerified,
      sourceUrl: item.SourceUrl,
      notes: item.Notes
    };
  }
}
