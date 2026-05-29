import { SPHttpClient } from '@microsoft/sp-http';

export interface IItsmHostProps {
  description: string;
  isDarkTheme: boolean;
  environmentMessage: string;
  hasTeamsContext: boolean;
  userDisplayName: string;
  userEmail: string;
  siteUrl: string;
  spHttpClient: SPHttpClient;
}
