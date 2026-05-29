#Requires -Version 7.0
#Requires -Modules @{ ModuleName='PnP.PowerShell'; ModuleVersion='2.4.0' }

# Shared idempotent helpers for ITSM SharePoint provisioning.
# All Ensure-* functions are no-ops when the target state already matches.
# All emit one of: [CREATED], [UPDATED], [NO-CHANGE], [SKIPPED] per element.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-StateLine {
    param(
        [Parameter(Mandatory)][ValidateSet('CREATED','UPDATED','NO-CHANGE','SKIPPED','ERROR')][string]$State,
        [Parameter(Mandatory)][string]$Object,
        [string]$Detail = ''
    )
    $color = switch ($State) {
        'CREATED'   { 'Green' }
        'UPDATED'   { 'Yellow' }
        'NO-CHANGE' { 'Gray' }
        'SKIPPED'   { 'DarkGray' }
        'ERROR'     { 'Red' }
    }
    Write-Host ("[{0,-9}] {1} {2}" -f $State, $Object, $Detail) -ForegroundColor $color
}

function Ensure-PnPList {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Title,
        [string]$Description = '',
        [ValidateSet('GenericList','DocumentLibrary')][string]$Template = 'GenericList',
        [bool]$EnableVersioning = $true,
        [int]$MajorVersionLimit = 50,
        [bool]$OnQuickLaunch = $false
    )

    $existing = Get-PnPList -Identity $Title -ErrorAction SilentlyContinue
    if ($null -eq $existing) {
        New-PnPList -Title $Title -Template $Template -OnQuickLaunch:$OnQuickLaunch | Out-Null
        $existing = Get-PnPList -Identity $Title
        Write-StateLine -State CREATED -Object "List: $Title"
    } else {
        Write-StateLine -State 'NO-CHANGE' -Object "List: $Title" -Detail "(exists)"
    }

    $needsUpdate = $false
    $updateArgs = @{ Identity = $Title }
    if ($Description -and $existing.Description -ne $Description) {
        $updateArgs.Description = $Description; $needsUpdate = $true
    }
    if ($existing.EnableVersioning -ne $EnableVersioning) {
        $updateArgs.EnableVersioning = $EnableVersioning; $needsUpdate = $true
    }
    # PnP.PowerShell 3.x renamed MajorVersionLimit -> MajorVersions
    if ($EnableVersioning -and $existing.MajorVersionLimit -ne $MajorVersionLimit) {
        $updateArgs.MajorVersions = $MajorVersionLimit; $needsUpdate = $true
    }
    if ($needsUpdate) {
        Set-PnPList @updateArgs | Out-Null
        Write-StateLine -State UPDATED -Object "List: $Title" -Detail "(metadata)"
    }

    return Get-PnPList -Identity $Title
}

function Ensure-PnPField {
    <#
    .SYNOPSIS
    Idempotently creates or updates a SharePoint field on a list.
    .PARAMETER Spec
    Hashtable with keys:
      InternalName (string, required)
      DisplayName  (string, required)
      Type         (Text|Note|Choice|Number|Currency|DateTime|Boolean|User|UserMulti|Lookup|LookupMulti|Calculated)
      Required     (bool, default $false)
      Indexed      (bool, default $false)
      Description  (string, optional)
      Choices      (string[], for Choice type)
      DefaultValue (string, optional)
      RichText     (bool, for Note type)
      AppendOnly   (bool, for Note type)
      LookupList   (string, for Lookup* — list title)
      LookupField  (string, for Lookup* — field internal name to display)
      MaxLength    (int, for Text type)
      Formula      (string, for Calculated)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ListTitle,
        [Parameter(Mandatory)][hashtable]$Spec
    )

    $internal = $Spec.InternalName
    $display  = $Spec.DisplayName
    $type     = $Spec.Type
    $required = if ($Spec.ContainsKey('Required')) { [bool]$Spec.Required } else { $false }
    $indexed  = if ($Spec.ContainsKey('Indexed'))  { [bool]$Spec.Indexed }  else { $false }
    $hasDefault = $Spec.ContainsKey('DefaultValue')

    $existing = Get-PnPField -List $ListTitle -Identity $internal -ErrorAction SilentlyContinue
    if ($null -eq $existing) {
        switch ($type) {
            'Choice' {
                Add-PnPField -List $ListTitle -InternalName $internal -DisplayName $display `
                    -Type Choice -Choices $Spec.Choices -Required:$required | Out-Null
            }
            'Lookup' {
                $lookupListId = (Get-PnPList -Identity $Spec.LookupList).Id
                $lookupField  = if ($Spec.LookupField) { $Spec.LookupField } else { 'Title' }
                $xml = @"
<Field Type='Lookup' Name='$internal' StaticName='$internal' DisplayName='$display' List='{$lookupListId}' ShowField='$lookupField' Required='$($required.ToString().ToUpper())' />
"@
                Add-PnPFieldFromXml -List $ListTitle -FieldXml $xml | Out-Null
            }
            'LookupMulti' {
                $lookupListId = (Get-PnPList -Identity $Spec.LookupList).Id
                $lookupField  = if ($Spec.LookupField) { $Spec.LookupField } else { 'Title' }
                $xml = @"
<Field Type='LookupMulti' Mult='TRUE' Name='$internal' StaticName='$internal' DisplayName='$display' List='{$lookupListId}' ShowField='$lookupField' Required='$($required.ToString().ToUpper())' />
"@
                Add-PnPFieldFromXml -List $ListTitle -FieldXml $xml | Out-Null
            }
            'User' {
                Add-PnPField -List $ListTitle -InternalName $internal -DisplayName $display `
                    -Type User -Required:$required | Out-Null
            }
            'UserMulti' {
                $xml = @"
<Field Type='UserMulti' Mult='TRUE' Name='$internal' StaticName='$internal' DisplayName='$display' UserSelectionMode='PeopleOnly' Required='$($required.ToString().ToUpper())' />
"@
                Add-PnPFieldFromXml -List $ListTitle -FieldXml $xml | Out-Null
            }
            'Note' {
                $rich = if ($Spec.ContainsKey('RichText')) { [bool]$Spec.RichText } else { $false }
                $append = if ($Spec.ContainsKey('AppendOnly')) { [bool]$Spec.AppendOnly } else { $false }
                $richAttr = if ($rich) { 'TRUE' } else { 'FALSE' }
                $appendAttr = if ($append) { 'TRUE' } else { 'FALSE' }
                $xml = @"
<Field Type='Note' Name='$internal' StaticName='$internal' DisplayName='$display' RichText='$richAttr' AppendOnly='$appendAttr' Required='$($required.ToString().ToUpper())' />
"@
                Add-PnPFieldFromXml -List $ListTitle -FieldXml $xml | Out-Null
            }
            'Calculated' {
                $formula = $Spec.Formula
                $resultType = if ($Spec.ResultType) { $Spec.ResultType } else { 'Text' }
                $xml = @"
<Field Type='Calculated' Name='$internal' StaticName='$internal' DisplayName='$display' ResultType='$resultType'>
  <Formula>$formula</Formula>
</Field>
"@
                Add-PnPFieldFromXml -List $ListTitle -FieldXml $xml | Out-Null
            }
            default {
                Add-PnPField -List $ListTitle -InternalName $internal -DisplayName $display `
                    -Type $type -Required:$required | Out-Null
            }
        }
        Write-StateLine -State CREATED -Object "Field: ${ListTitle}.${internal}" -Detail "($type)"
    } else {
        # Existing field — update display name, required/default if drifted
        $needsUpdate = $false
        $values = @{
            Title    = $display
            Required = $required
        }
        if ($existing.Title -ne $display) { $needsUpdate = $true }
        if ($existing.Required -ne $required) { $needsUpdate = $true }
        if ($hasDefault -and $existing.DefaultValue -ne [string]$Spec.DefaultValue) {
            $values.DefaultValue = [string]$Spec.DefaultValue
            $needsUpdate = $true
        }
        if ($needsUpdate) {
            Set-PnPField -List $ListTitle -Identity $internal -Values $values | Out-Null
            Write-StateLine -State UPDATED -Object "Field: ${ListTitle}.${internal}"
        } else {
            Write-StateLine -State 'NO-CHANGE' -Object "Field: ${ListTitle}.${internal}"
        }
    }

    if ($hasDefault) {
        $field = Get-PnPField -List $ListTitle -Identity $internal
        if ($field.DefaultValue -ne [string]$Spec.DefaultValue) {
            Set-PnPField -List $ListTitle -Identity $internal -Values @{ DefaultValue = [string]$Spec.DefaultValue } | Out-Null
            Write-StateLine -State UPDATED -Object "Default: ${ListTitle}.${internal}" -Detail "(set default)"
        }
    }

    if ($indexed) {
        $field = Get-PnPField -List $ListTitle -Identity $internal
        if (-not $field.Indexed) {
            Set-PnPField -List $ListTitle -Identity $internal -Values @{ Indexed = $true } | Out-Null
            Write-StateLine -State UPDATED -Object "Index: ${ListTitle}.${internal}" -Detail "(set indexed)"
        }
    }
}

function Ensure-PnPListVersioning {
    param(
        [Parameter(Mandatory)][string]$ListTitle,
        [bool]$Enable = $true,
        [int]$MajorVersionLimit = 50
    )
    $list = Get-PnPList -Identity $ListTitle
    if ($list.EnableVersioning -ne $Enable -or $list.MajorVersionLimit -ne $MajorVersionLimit) {
        Set-PnPList -Identity $ListTitle -EnableVersioning $Enable -MajorVersions $MajorVersionLimit | Out-Null
        Write-StateLine -State UPDATED -Object "Versioning: $ListTitle" -Detail "(enabled=$Enable, limit=$MajorVersionLimit)"
    } else {
        Write-StateLine -State 'NO-CHANGE' -Object "Versioning: $ListTitle"
    }
}

function Connect-ItsmTenantPilot {
    <#
    .SYNOPSIS
    Pilot-mode silent connect using a local cert file (no Key Vault dependency).
    Reads $env:ITSM_PILOT_CLIENT_ID, $env:ITSM_PILOT_TENANT, $env:ITSM_PILOT_CERT_PATH, $env:ITSM_PILOT_CERT_PASSWORD if set.
    Falls back to defaults pointed at the SP-IT-Provisioning-AppOnly app + local cert.
    #>
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [string]$ClientId,
        [string]$Tenant   = 'contoso.onmicrosoft.com',
        [string]$CertificatePath,
        [SecureString]$CertificatePassword
    )

    if (-not $ClientId) { $ClientId = $env:ITSM_PILOT_CLIENT_ID }
    if (-not $CertificatePath) {
        $CertificatePath = if ($env:ITSM_PILOT_CERT_PATH) { $env:ITSM_PILOT_CERT_PATH } else { "C:\Users\ninih\.itsm-pilot\certs\SP-IT-Provisioning-AppOnly.pfx" }
    }
    if (-not $CertificatePassword) {
        $certPwd = if ($env:ITSM_PILOT_CERT_PASSWORD) { $env:ITSM_PILOT_CERT_PASSWORD } else { 'pilot-only-not-secret' }
        $CertificatePassword = ConvertTo-SecureString -AsPlainText -Force -String $certPwd
    }

    if (-not $ClientId) {
        throw "ClientId not provided and `$env:ITSM_PILOT_CLIENT_ID not set. After running setup-cert-auth, set the env var to the AzureAppId returned by Register-PnPAzureADApp."
    }
    if (-not (Test-Path $CertificatePath)) {
        throw "Certificate not found at $CertificatePath. Run setup-cert-auth.ps1 first."
    }

    Write-Host "Connecting to $SiteUrl as app $ClientId via local cert..." -ForegroundColor Cyan
    Connect-PnPOnline `
        -Url $SiteUrl `
        -ClientId $ClientId `
        -Tenant $Tenant `
        -CertificatePath $CertificatePath `
        -CertificatePassword $CertificatePassword `
        -ErrorAction Stop
    Write-Host "Connected silently (no device code)." -ForegroundColor Green
}

function Connect-ItsmTenant {
    param(
        [Parameter(Mandatory)][string]$SiteUrl,
        [Parameter(Mandatory)][string]$AppId,
        [Parameter(Mandatory)][string]$KeyVaultName,
        [Parameter(Mandatory)][string]$CertificateName
    )

    Write-Host "Connecting to $SiteUrl as app $AppId (cert from $KeyVaultName/$CertificateName)..." -ForegroundColor Cyan

    # Pull cert from Key Vault
    $cert = Get-AzKeyVaultCertificate -VaultName $KeyVaultName -Name $CertificateName -ErrorAction Stop
    $secret = Get-AzKeyVaultSecret -VaultName $KeyVaultName -Name $cert.Name -AsPlainText
    $certBytes = [Convert]::FromBase64String($secret)
    $tempCertPath = Join-Path ([System.IO.Path]::GetTempPath()) "$([Guid]::NewGuid()).pfx"
    [System.IO.File]::WriteAllBytes($tempCertPath, $certBytes)

    try {
        $tenant = ($SiteUrl -replace '^https://([^.]+)\..*$', '$1') + '.onmicrosoft.com'
        Connect-PnPOnline -Url $SiteUrl -ClientId $AppId -CertificatePath $tempCertPath -Tenant $tenant
        Write-Host "Connected." -ForegroundColor Green
    } finally {
        if (Test-Path $tempCertPath) { Remove-Item $tempCertPath -Force }
    }
}
