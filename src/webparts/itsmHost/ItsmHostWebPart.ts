import * as React from 'react';
import * as ReactDom from 'react-dom';
import { Version } from '@microsoft/sp-core-library';
import {
  type IPropertyPaneConfiguration,
  PropertyPaneTextField
} from '@microsoft/sp-property-pane';
import { BaseClientSideWebPart } from '@microsoft/sp-webpart-base';
import { IReadonlyTheme } from '@microsoft/sp-component-base';

import * as strings from 'ItsmHostWebPartStrings';
import ItsmHost from './components/ItsmHost';
import { IItsmHostProps } from './components/IItsmHostProps';

export interface IItsmHostWebPartProps {
  description: string;
}

export default class ItsmHostWebPart extends BaseClientSideWebPart<IItsmHostWebPartProps> {
  private static readonly _hostChromeStyleId: string = 'itsm-host-chrome';

  private _isDarkTheme: boolean = false;
  private _environmentMessage: string = '';

  public render(): void {
    this._hideHostChrome();

    const element: React.ReactElement<IItsmHostProps> = React.createElement(
      ItsmHost,
      {
        description: this.properties.description,
        isDarkTheme: this._isDarkTheme,
        environmentMessage: this._environmentMessage,
        hasTeamsContext: !!this.context.sdks.microsoftTeams,
        userDisplayName: this.context.pageContext.user.displayName,
        userEmail: this.context.pageContext.user.email,
        siteUrl: this.context.pageContext.web.absoluteUrl,
        spHttpClient: this.context.spHttpClient
      }
    );

    ReactDom.render(element, this.domElement);
  }

  protected onInit(): Promise<void> {
    return this._getEnvironmentMessage().then(message => {
      this._environmentMessage = message;
    });
  }

  private _hideHostChrome(): void {
    if (document.getElementById(ItsmHostWebPart._hostChromeStyleId)) {
      return;
    }

    const style: HTMLStyleElement = document.createElement('style');
    style.id = ItsmHostWebPart._hostChromeStyleId;
    style.textContent = `
      #sp-appBar,
      #spCommandBar,
      #spSiteHeader,
      #SuiteNavWrapper,
      #CommentsWrapper,
      #spLeftNav,
      [data-automation-id="SiteHeader"],
      [data-automation-id="pageHeader"],
      [data-automation-id="pageCommandBar"],
      .ms-HorizontalNav,
      .sp-appBar,
      .spAppAndPropertyPanelContainer .sp-appBar,
      .spAppAndPropertyPanelContainer .sp-appBar-mobile,
      .spAppAndPropertyPanelContainer [role="banner"],
      .spAppAndPropertyPanelContainer [data-sp-feature-tag="Site header host"],
      .spAppAndPropertyPanelContainer [data-sp-feature-tag="Comments"] {
        display: none !important;
        visibility: hidden !important;
        height: 0 !important;
        min-height: 0 !important;
        max-height: 0 !important;
        overflow: hidden !important;
      }

      #spPageCanvasContent,
      #spPageCanvasContent > div,
      .SPCanvas,
      .Canvas,
      .CanvasComponent,
      .CanvasZone,
      .CanvasSection,
      .ControlZone,
      .CanvasZoneContainer,
      .spAppAndPropertyPanelContainer,
      .sp-appBar-parent,
      [data-automation-id="Canvas"],
      [data-automation-id="CanvasControl"],
      [data-automation-id="CanvasZone"],
      [data-automation-id="CanvasSection"],
      [data-automation-id="CanvasZone-SectionContainer"] {
        margin: 0 !important;
        padding: 0 !important;
        max-width: none !important;
        width: 100% !important;
      }

      #spPageCanvasContent,
      .CanvasComponent,
      .CanvasZone,
      .CanvasSection,
      .ControlZone,
      [data-automation-id="Canvas"],
      [data-automation-id="CanvasControl"] {
        min-height: 100vh !important;
      }

      .CanvasComponent.LCS .CanvasZone {
        max-width: none !important;
      }

      [data-automation-id="CanvasControl"] {
        padding: 0 !important;
      }
    `;
    document.head.appendChild(style);
  }

  private _getEnvironmentMessage(): Promise<string> {
    if (!!this.context.sdks.microsoftTeams) {
      return this.context.sdks.microsoftTeams.teamsJs.app.getContext()
        .then(context => {
          switch (context.app.host.name) {
            case 'Office':
              return this.context.isServedFromLocalhost ? strings.AppLocalEnvironmentOffice : strings.AppOfficeEnvironment;
            case 'Outlook':
              return this.context.isServedFromLocalhost ? strings.AppLocalEnvironmentOutlook : strings.AppOutlookEnvironment;
            case 'Teams':
            case 'TeamsModern':
              return this.context.isServedFromLocalhost ? strings.AppLocalEnvironmentTeams : strings.AppTeamsTabEnvironment;
            default:
              return strings.UnknownEnvironment;
          }
        });
    }

    return Promise.resolve(this.context.isServedFromLocalhost ? strings.AppLocalEnvironmentSharePoint : strings.AppSharePointEnvironment);
  }

  protected onThemeChanged(currentTheme: IReadonlyTheme | undefined): void {
    if (!currentTheme) {
      return;
    }

    this._isDarkTheme = !!currentTheme.isInverted;
    const { semanticColors } = currentTheme;

    if (semanticColors) {
      this.domElement.style.setProperty('--bodyText', semanticColors.bodyText || null);
      this.domElement.style.setProperty('--link', semanticColors.link || null);
      this.domElement.style.setProperty('--linkHovered', semanticColors.linkHovered || null);
    }
  }

  protected onDispose(): void {
    document.getElementById(ItsmHostWebPart._hostChromeStyleId)?.remove();
    ReactDom.unmountComponentAtNode(this.domElement);
  }

  protected get dataVersion(): Version {
    return Version.parse('1.0');
  }

  protected getPropertyPaneConfiguration(): IPropertyPaneConfiguration {
    return {
      pages: [
        {
          header: {
            description: strings.PropertyPaneDescription
          },
          groups: [
            {
              groupName: strings.BasicGroupName,
              groupFields: [
                PropertyPaneTextField('description', {
                  label: strings.DescriptionFieldLabel
                })
              ]
            }
          ]
        }
      ]
    };
  }
}
