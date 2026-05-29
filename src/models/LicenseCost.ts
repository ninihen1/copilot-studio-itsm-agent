export interface LicenseCost {
  id: number;
  title: string;
  skuPartNumber: string;
  skuId?: string;
  officialProductName?: string;
  listPriceMonthly?: number;
  negotiatedPriceMonthly?: number;
  currency?: string;
  billingCycle?: string;
  lastVerified?: string;
  sourceUrl?: string;
  notes?: string;
}
