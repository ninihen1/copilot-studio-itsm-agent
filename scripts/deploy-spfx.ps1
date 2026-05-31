#Requires -Version 7.0

<#
.SYNOPSIS
Uploads and deploys the ITSM SPFx .sppkg package to the SharePoint site-collection app catalog (on /sites/ITSM).

.DESCRIPTION
Fallback deployment path for local/admin use when GitHub Actions is not appropriate.
Supports CLI for Microsoft 365 or PnP.PowerShell certificate authentication.

Required values can be passed as parameters or environment variables:
M365_TENANT_ID, M365_APP_ID, M365_CERT_PATH or M365_CERT_BASE64,
M365_CERT_PASSWORD, SPFX_APP_CATALOG_URL, SPFX_PACKAGE_PATH.
#>

[CmdletBinding()]
param(
    [string] $EnvFile = $(if ($env:ITSM_ENV_FILE) { $env:ITSM_ENV_FILE } elseif (Test-Path -LiteralPath '.env.production') { '.env.production' } else { '' }),

    [ValidateSet('CLI', 'PnP')]
    [string] $Tool = $(if ($env:SPFX_DEPLOY_TOOL) { $env:SPFX_DEPLOY_TOOL } else { 'CLI' }),

    [string] $TenantId = $env:M365_TENANT_ID,
    [string] $AppId = $env:M365_APP_ID,
    [string] $AppCatalogUrl = $(if ($env:SPFX_APP_CATALOG_URL) { $env:SPFX_APP_CATALOG_URL } else { 'https://contoso.sharepoint.com/sites/ITSM' }),
    [string] $PackagePath = $(if ($env:SPFX_PACKAGE_PATH) { $env:SPFX_PACKAGE_PATH } else { 'sharepoint/solution/itsm-frontend.sppkg' }),
    [string] $CertificatePath = $env:M365_CERT_PATH,
    [string] $CertificateBase64 = $env:M365_CERT_BASE64,
    [string] $CertificatePassword = $env:M365_CERT_PASSWORD,
    [switch] $SkipFeatureDeployment = $true,
    [switch] $KeepDecodedCertificate
)

$ErrorActionPreference = 'Stop'

if (-not [string]::IsNullOrWhiteSpace($EnvFile)) {
    $loader = Join-Path $PSScriptRoot 'load-env.ps1'
    if (-not (Test-Path -LiteralPath $loader)) {
        throw "Environment loader not found: $loader"
    }

    & $loader -Path $EnvFile | Out-Host

    if (-not $PSBoundParameters.ContainsKey('Tool') -and $env:SPFX_DEPLOY_TOOL) { $Tool = $env:SPFX_DEPLOY_TOOL }
    if (-not $PSBoundParameters.ContainsKey('TenantId') -and $env:M365_TENANT_ID) { $TenantId = $env:M365_TENANT_ID }
    if (-not $PSBoundParameters.ContainsKey('AppId') -and $env:M365_APP_ID) { $AppId = $env:M365_APP_ID }
    if (-not $PSBoundParameters.ContainsKey('AppCatalogUrl') -and $env:SPFX_APP_CATALOG_URL) { $AppCatalogUrl = $env:SPFX_APP_CATALOG_URL }
    if (-not $PSBoundParameters.ContainsKey('PackagePath') -and $env:SPFX_PACKAGE_PATH) { $PackagePath = $env:SPFX_PACKAGE_PATH }
    if (-not $PSBoundParameters.ContainsKey('CertificatePath') -and $env:M365_CERT_PATH) { $CertificatePath = $env:M365_CERT_PATH }
    if (-not $PSBoundParameters.ContainsKey('CertificateBase64') -and $env:M365_CERT_BASE64) { $CertificateBase64 = $env:M365_CERT_BASE64 }
    if (-not $PSBoundParameters.ContainsKey('CertificatePassword') -and $env:M365_CERT_PASSWORD) { $CertificatePassword = $env:M365_CERT_PASSWORD }
}

function Assert-Value {
    param(
        [string] $Name,
        [string] $Value
    )
    if ([string]::IsNullOrWhiteSpace($Value)) {
        throw "Missing required value: $Name"
    }
}

function Resolve-CertificatePath {
    if (-not [string]::IsNullOrWhiteSpace($CertificatePath)) {
        if (-not (Test-Path -LiteralPath $CertificatePath)) {
            throw "CertificatePath does not exist: $CertificatePath"
        }
        return (Resolve-Path -LiteralPath $CertificatePath).Path
    }

    if ([string]::IsNullOrWhiteSpace($CertificateBase64)) {
        throw "Provide either CertificatePath/M365_CERT_PATH or CertificateBase64/M365_CERT_BASE64."
    }

    $decodedPath = Join-Path $PWD '.spfx-deploy-cert.pfx'
    [IO.File]::WriteAllBytes($decodedPath, [Convert]::FromBase64String($CertificateBase64))
    return (Resolve-Path -LiteralPath $decodedPath).Path
}

Assert-Value -Name 'TenantId' -Value $TenantId
Assert-Value -Name 'AppId' -Value $AppId
Assert-Value -Name 'AppCatalogUrl' -Value $AppCatalogUrl
Assert-Value -Name 'PackagePath' -Value $PackagePath
Assert-Value -Name 'CertificatePassword' -Value $CertificatePassword

if (-not (Test-Path -LiteralPath $PackagePath)) {
    throw "SPFx package not found: $PackagePath. Run npm run ci first."
}

$resolvedPackagePath = (Resolve-Path -LiteralPath $PackagePath).Path
$resolvedCertPath = Resolve-CertificatePath
$packageName = Split-Path -Path $resolvedPackagePath -Leaf

try {
    switch ($Tool) {
        'CLI' {
            $m365 = Get-Command m365 -ErrorAction SilentlyContinue
            if (-not $m365) {
                throw "CLI for Microsoft 365 not found. Install with: npm install --global @pnp/cli-microsoft365"
            }

            Write-Host "Logging in to Microsoft 365 with certificate auth..."
            & m365 login `
                --authType certificate `
                --tenant $TenantId `
                --appId $AppId `
                --certificateFile $resolvedCertPath `
                --password $CertificatePassword

            Write-Host "Uploading $packageName to $AppCatalogUrl..."
            & m365 spo app add `
                --appCatalogScope sitecollection `
                --appCatalogUrl $AppCatalogUrl `
                --filePath $resolvedPackagePath `
                --overwrite

            Write-Host "Deploying $packageName..."
            $deployArgs = @(
                'spo', 'app', 'deploy',
                '--appCatalogScope', 'sitecollection',
                '--appCatalogUrl', $AppCatalogUrl,
                '--name', $packageName
            )
            if ($SkipFeatureDeployment) {
                $deployArgs += '--skipFeatureDeployment'
            }
            & m365 @deployArgs

            & m365 logout
        }

        'PnP' {
            $pnp = Get-Module -ListAvailable -Name PnP.PowerShell | Select-Object -First 1
            if (-not $pnp) {
                throw "PnP.PowerShell not found. Install with: Install-Module PnP.PowerShell -Scope CurrentUser"
            }

            Import-Module PnP.PowerShell

            Write-Host "Connecting to $AppCatalogUrl with certificate auth..."
            Connect-PnPOnline `
                -Url $AppCatalogUrl `
                -Tenant $TenantId `
                -ClientId $AppId `
                -CertificatePath $resolvedCertPath `
                -CertificatePassword (ConvertTo-SecureString $CertificatePassword -AsPlainText -Force)

            Write-Host "Uploading and publishing $packageName..."
            Add-PnPApp -Path $resolvedPackagePath -Scope Site -Overwrite -Publish
        }
    }

    Write-Host "SPFx deployment completed: $packageName"
}
finally {
    if (-not $KeepDecodedCertificate -and [string]::IsNullOrWhiteSpace($CertificatePath) -and (Test-Path -LiteralPath $resolvedCertPath)) {
        Remove-Item -LiteralPath $resolvedCertPath -Force
    }
}
