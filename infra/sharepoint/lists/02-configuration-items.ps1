#Requires -Version 7.0

# Configuration Items list — the CMDB.
# Source: sharepoint-itsm-schema.xlsx, sheet "6. Configuration Items"
. (Join-Path $PSScriptRoot '_helpers.ps1')

function Provision-ConfigurationItemsList {
    param([string]$ListTitle = 'Configuration Items')
    Write-Host "`n=== $ListTitle ===" -ForegroundColor Cyan

    Ensure-PnPList -Title $ListTitle `
        -Description 'CMDB. Anything tickets can reference: services, applications, infrastructure, locations.' `
        -EnableVersioning $true -MajorVersionLimit 20 | Out-Null

    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='CiName'; DisplayName='Configuration Item Name'; Type='Text'; Required=$true; Indexed=$true; MaxLength=200 }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='CiClass'; DisplayName='Class'; Type='Choice'; Choices=@('Application','Service','Server','Database','Network Device','Storage','Workstation','Mobile Device','Cloud Subscription','Vendor','Other'); Required=$true; Indexed=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ParentCi'; DisplayName='Parent Configuration Item'; Type='Lookup'; LookupList='Configuration Items'; LookupField='Title' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='BusinessOwner'; DisplayName='Business Owner'; Type='User' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='TechnicalOwner'; DisplayName='Technical Owner'; Type='User' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Environment'; DisplayName='Environment'; Type='Choice'; Choices=@('Production','Staging','Development','Test','Disaster Recovery') }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='OperationalStatus'; DisplayName='Operational Status'; Type='Choice'; Choices=@('Operational','Degraded','Down','Retired'); Indexed=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='UrlOrEndpoint'; DisplayName='URL / Endpoint'; Type='Text'; MaxLength=500 }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Description'; DisplayName='Description'; Type='Note'; RichText=$false }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Status'; DisplayName='Lifecycle Status'; Type='Choice'; Choices=@('active','deprecated'); Required=$true; DefaultValue='active' }
}

