declare interface IItsmHostWebPartStrings {
  PropertyPaneDescription: string;
  BasicGroupName: string;
  DescriptionFieldLabel: string;
  AppLocalEnvironmentSharePoint: string;
  AppSharePointEnvironment: string;
  AppLocalEnvironmentTeams: string;
  AppTeamsTabEnvironment: string;
  AppLocalEnvironmentOffice: string;
  AppOfficeEnvironment: string;
  AppLocalEnvironmentOutlook: string;
  AppOutlookEnvironment: string;
  UnknownEnvironment: string;
}

declare module 'ItsmHostWebPartStrings' {
  const strings: IItsmHostWebPartStrings;
  export = strings;
}
