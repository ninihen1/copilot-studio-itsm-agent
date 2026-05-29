import { ISharePointServiceContext, SharePointServiceBase } from './SharePointServiceBase';

interface IListResponse<T> { value: T[]; }

interface IKnowledgeListItem {
  Id: number;
  Title: string;
  ArticleNumber?: string;
  Summary?: string;
  ArticleBody?: string;
  Category?: unknown;
}

export interface KnowledgeArticle {
  id: number;
  title: string;
  articleNumber: string;
  summary: string;
  body: string;
  category?: string;
}

export class KnowledgeService extends SharePointServiceBase {
  public constructor(context: ISharePointServiceContext) { super(context); }

  public async search(_query: string): Promise<KnowledgeArticle[]> {
    const select = '$select=Id,Title,ArticleNumber,Summary,ArticleBody,Category/Title';
    const response = await this.get<IListResponse<IKnowledgeListItem>>(
      this.listItemsUrl('Knowledge Base',
        `?${select}&$expand=Category&$filter=ArticleStatus eq 'Published'&$orderby=PublishedDate desc&$top=20`));

    return response.value.map(item => ({
      id: item.Id,
      title: item.Title,
      articleNumber: item.ArticleNumber || `KB-${item.Id}`,
      summary: item.Summary || '',
      body: item.ArticleBody || '',
      category: this.lookupValue(item.Category)
    }));
  }
}
