import { SPHttpClient, SPHttpClientResponse } from '@microsoft/sp-http';

export interface ISharePointServiceContext {
  siteUrl: string;
  spHttpClient?: SPHttpClient;
}

export abstract class SharePointServiceBase {
  protected constructor(protected readonly context: ISharePointServiceContext) {}

  protected listItemsUrl(listTitle: string, query: string = ''): string {
    const escapedTitle = listTitle.replace(/'/g, "''");
    return `/_api/web/lists/getbytitle('${escapedTitle}')/items${query}`;
  }

  protected async get<T>(relativeUrl: string): Promise<T> {
    if (!this.context.spHttpClient) {
      throw new Error('SPHttpClient is not configured yet.');
    }

    // SharePoint REST GETs can be served stale from the browser/proxy cache,
    // which makes the portal show old data until a full page reload. A per-request
    // cache-buster plus no-cache headers force a fresh read every time.
    const separator = relativeUrl.indexOf('?') >= 0 ? '&' : '?';
    const url = `${this.context.siteUrl}${relativeUrl}${separator}_=${Date.now()}`;

    const response: SPHttpClientResponse = await this.context.spHttpClient.get(
      url,
      SPHttpClient.configurations.v1,
      {
        headers: {
          'Cache-Control': 'no-cache',
          Pragma: 'no-cache'
        }
      }
    );

    if (!response.ok) {
      const detail = await response.text();
      const message = detail ? ` - ${detail.substring(0, 700)}` : '';
      throw new Error(`SharePoint GET failed: ${response.status} ${response.statusText} ${relativeUrl}${message}`);
    }

    return response.json() as Promise<T>;
  }

  protected async post<T>(relativeUrl: string, body: unknown): Promise<T> {
    if (!this.context.spHttpClient) {
      throw new Error('SPHttpClient is not configured yet.');
    }

    const response: SPHttpClientResponse = await this.context.spHttpClient.post(
      `${this.context.siteUrl}${relativeUrl}`,
      SPHttpClient.configurations.v1,
      {
        headers: {
          Accept: 'application/json;odata=nometadata',
          'Content-Type': 'application/json;odata=nometadata'
        },
        body: JSON.stringify(body)
      }
    );

    if (!response.ok) {
      const detail = await response.text();
      const message = detail ? ` - ${detail.substring(0, 700)}` : '';
      throw new Error(`SharePoint POST failed: ${response.status} ${response.statusText} ${relativeUrl}${message}`);
    }

    return response.json() as Promise<T>;
  }

  protected async merge(relativeUrl: string, body: unknown): Promise<void> {
    if (!this.context.spHttpClient) {
      throw new Error('SPHttpClient is not configured yet.');
    }

    const response: SPHttpClientResponse = await this.context.spHttpClient.post(
      `${this.context.siteUrl}${relativeUrl}`,
      SPHttpClient.configurations.v1,
      {
        headers: {
          Accept: 'application/json;odata=nometadata',
          'Content-Type': 'application/json;odata=nometadata',
          'IF-MATCH': '*',
          'X-HTTP-Method': 'MERGE'
        },
        body: JSON.stringify(body)
      }
    );

    if (!response.ok) {
      const detail = await response.text();
      const message = detail ? ` - ${detail.substring(0, 700)}` : '';
      throw new Error(`SharePoint MERGE failed: ${response.status} ${response.statusText} ${relativeUrl}${message}`);
    }
  }

  protected async getCurrentUserId(): Promise<number> {
    const user = await this.get<{ Id: number }>('/_api/web/currentuser?$select=Id');
    return user.Id;
  }

  protected async ensureUserId(loginName: string): Promise<number> {
    const user = await this.post<{ Id: number }>('/_api/web/ensureuser', {
      logonName: loginName
    });
    return user.Id;
  }

  protected lookupValue(value: unknown): string | undefined {
    if (!value) {
      return undefined;
    }

    if (typeof value === 'string') {
      return value;
    }

    const candidate = value as { Title?: string; LookupValue?: string; EMail?: string };
    return candidate.Title || candidate.LookupValue || candidate.EMail;
  }

  protected userValue(value: unknown): string | undefined {
    if (!value) {
      return undefined;
    }

    const candidate = value as { Title?: string; EMail?: string };
    return candidate.EMail || candidate.Title;
  }

  protected escapeODataString(value: string): string {
    return value.replace(/'/g, "''");
  }
}
