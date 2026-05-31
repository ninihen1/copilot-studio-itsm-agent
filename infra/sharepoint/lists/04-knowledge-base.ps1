#Requires -Version 7.0

# Knowledge Base list — published articles and runbooks.
# Source: sharepoint-itsm-schema.xlsx, sheet "8. Knowledge Base"
. (Join-Path $PSScriptRoot '_helpers.ps1')

function Provision-KnowledgeBaseList {
    param([string]$ListTitle = 'Knowledge Base')
    Write-Host "`n=== $ListTitle ===" -ForegroundColor Cyan

    Ensure-PnPList -Title $ListTitle `
        -Description 'Published KB articles. Read by the Triage Agent and Self-Service Resolver for deflection.' `
        -EnableVersioning $true -MajorVersionLimit 50 | Out-Null

    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ArticleNumber'; DisplayName='Article Number'; Type='Text'; Required=$true; Indexed=$true; MaxLength=32; Description='KB-prefixed unique identifier' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Summary'; DisplayName='Summary'; Type='Note'; RichText=$false; Required=$true; Description='1-2 sentence summary used in agent search results' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Body'; DisplayName='Body'; Type='Note'; RichText=$true; Description='Full article content, rich text' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Category'; DisplayName='Category'; Type='Lookup'; LookupList='Categories'; LookupField='Title'; Indexed=$true }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Audience'; DisplayName='Audience'; Type='Choice'; Choices=@('All Employees','IT Staff Only','Managers Only','Restricted'); Required=$true; Indexed=$true; DefaultValue='All Employees' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ArticleStatus'; DisplayName='Status'; Type='Choice'; Choices=@('Draft','Review','Published','Retired'); Required=$true; Indexed=$true; DefaultValue='Draft' }
    # Renamed Author -> KbAuthor: SharePoint silently rejects 'Author' as a custom internal name (collision with built-in Author = item creator).
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='KbAuthor'; DisplayName='Article Author'; Type='User'; Required=$true; Description='User who authored the KB article (avoids SP system Author column collision).' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Reviewer'; DisplayName='Reviewer'; Type='User'; Description='User who reviewed the KB article. No Kb-prefix needed — Reviewer is not an SP-reserved name (unlike Author).' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='PublishedDate'; DisplayName='Published Date'; Type='DateTime' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='RetireDate'; DisplayName='Retire Date'; Type='DateTime'; Description='When article should be reviewed for accuracy' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='Keywords'; DisplayName='Keywords'; Type='Text'; MaxLength=500; Description='Comma-separated terms to improve agent search match' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ViewCount'; DisplayName='View Count'; Type='Number' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='HelpfulCount'; DisplayName='Helpful Count'; Type='Number' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='NotHelpfulCount'; DisplayName='Not Helpful Count'; Type='Number' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='RelatedArticles'; DisplayName='Related Articles'; Type='LookupMulti'; LookupList='Knowledge Base'; LookupField='Title' }
    Ensure-PnPField -ListTitle $ListTitle -Spec @{ InternalName='ResolvesJobType'; DisplayName='Resolves Job Type'; Type='Text'; MaxLength=64; Description='Optional. If set, links this article to a JobType for proactive deflection.' }
}

