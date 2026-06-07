export interface LicenseCost {
  id: number;
  title: string;
  skuPartNumber: string;
  skuId?: string;
  owned?: boolean;
  officialProductName?: string;
  listPriceMonthly?: number;
  negotiatedPriceMonthly?: number;
  currency?: string;
  billingCycle?: string;
  lastVerified?: string;
  sourceUrl?: string;
  notes?: string;
}
