# Capability expansion 2026-06-01 — SharePoint deleted-site-collection restore Function
#
# Wraps PnP Restore-PnPTenantRecycleBinItem for the SP-IT-SharePoint executor (sharepoint.restoreSite).
# Restoring a deleted SITE COLLECTION is a SharePoint TENANT-ADMIN operation against the -admin URL —
# the site-scoped SP-IT-SharePoint connection used by the executor flow cannot do it, hence this Function.
#
# PREREQUISITES (deploy-time, batched):
#   - PnP.PowerShell module vendored into the Function App's Modules/ folder.
#   - A SharePoint-Administrator-privileged Entra app (app-only, cert auth). This is NOT the
#     site-scoped SP-IT-SharePoint app — restoring deleted sites needs the SharePoint Administrator role.
#   - Cert PFX in Key Vault (secret SP-IT-SharePoint-Admin-CertPfxBase64 + password secret),
#     loaded at cold start via the Function App's Managed Identity (MI needs Get on those secrets).
#   - App settings: ITSM_KEY_VAULT_NAME, ITSM_SPO_ADMIN_URL (https://<tenant>-admin.sharepoint.com),
#     SP_IT_SHAREPOINT_ADMIN_APPID, ITSM_TENANT_DOMAIN.
#
# Request (POST): { "siteUrl": "https://<tenant>.sharepoint.com/sites/<x>", "correlationId": "<ulid>" }
# Response 200:   { "ok": true, "siteUrl": "...", "correlationId": "..." }
# Response 4xx/5xx: { "ok": false, "error": "<code>", "reason": "<message>", "correlationId": "..." }

using namespace System.Net

param($Request, $TriggerMetadata)

$ErrorActionPreference = 'Stop'

$moduleRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'Modules'
if (Test-Path $moduleRoot) {
    $env:PSModulePath = "$moduleRoot$([System.IO.Path]::PathSeparator)$env:PSModulePath"
}

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.KeyVault -ErrorAction Stop
Import-Module PnP.PowerShell -ErrorAction Stop

function Send-Response {
    param([int]$StatusCode, [object]$Body)
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = $StatusCode
        Headers    = @{ 'Content-Type' = 'application/json' }
        Body       = ($Body | ConvertTo-Json -Depth 5 -Compress)
    })
}

# === 1. Parse + validate request ===
try {
    $body = $Request.Body
    if ($body -is [string]) { $body = $body | ConvertFrom-Json }
} catch {
    Send-Response -StatusCode 400 -Body @{ ok = $false; error = 'invalid_json'; reason = $_.Exception.Message }
    return
}

$siteUrl       = [string]$body.siteUrl
$correlationId = if ($body.correlationId) { [string]$body.correlationId } else { [guid]::NewGuid().ToString() }

if (-not $siteUrl) {
    Send-Response -StatusCode 400 -Body @{ ok = $false; error = 'missing_field'; reason = 'siteUrl is required'; correlationId = $correlationId }
    return
}

# === 2. Load admin cert (base64 PFX) from Key Vault via Managed Identity ===
if (-not $script:SpoAdminCertB64) {
    try {
        $kvName = $env:ITSM_KEY_VAULT_NAME
        $certSecret = if ($env:SPO_ADMIN_CERT_SECRET_NAME) { $env:SPO_ADMIN_CERT_SECRET_NAME } else { 'SP-IT-SharePoint-Admin-CertPfxBase64' }
        $pwdSecret  = if ($env:SPO_ADMIN_CERT_PASSWORD_NAME) { $env:SPO_ADMIN_CERT_PASSWORD_NAME } else { 'SP-IT-SharePoint-Admin-CertPassword' }
        if (-not $kvName) {
            Send-Response -StatusCode 500 -Body @{ ok = $false; error = 'missing_env'; reason = 'ITSM_KEY_VAULT_NAME env var not set'; correlationId = $correlationId }
            return
        }
        Disable-AzContextAutosave -Scope Process | Out-Null
        Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
        $script:SpoAdminCertB64 = (Get-AzKeyVaultSecret -VaultName $kvName -Name $certSecret -AsPlainText)
        $script:SpoAdminCertPwd = ConvertTo-SecureString -String (Get-AzKeyVaultSecret -VaultName $kvName -Name $pwdSecret -AsPlainText) -AsPlainText -Force
    } catch {
        Send-Response -StatusCode 503 -Body @{ ok = $false; error = 'cert_load_failed'; reason = $_.Exception.Message; correlationId = $correlationId }
        return
    }
}

$adminUrl = $env:ITSM_SPO_ADMIN_URL          # e.g. https://<tenant>-admin.sharepoint.com
$appId    = $env:SP_IT_SHAREPOINT_ADMIN_APPID
$tenant   = $env:ITSM_TENANT_DOMAIN
if (-not $adminUrl -or -not $appId -or -not $tenant) {
    Send-Response -StatusCode 500 -Body @{ ok = $false; error = 'missing_env'; reason = 'ITSM_SPO_ADMIN_URL, SP_IT_SHAREPOINT_ADMIN_APPID and ITSM_TENANT_DOMAIN must be set on the Function App'; correlationId = $correlationId }
    return
}

# === 3. Connect PnP to the admin endpoint + restore ===
try {
    Connect-PnPOnline -Url $adminUrl -ClientId $appId -Tenant $tenant -CertificateBase64Encoded $script:SpoAdminCertB64 -CertificatePassword $script:SpoAdminCertPwd -ErrorAction Stop
} catch {
    Send-Response -StatusCode 502 -Body @{ ok = $false; error = 'pnp_connect_failed'; reason = $_.Exception.Message; correlationId = $correlationId }
    return
}

try {
    Restore-PnPTenantRecycleBinItem -Url $siteUrl -Force -ErrorAction Stop | Out-Null
} catch {
    $exMsg = $_.Exception.Message
    Send-Response -StatusCode 500 -Body @{
        ok = $false
        error = if ($exMsg -match 'not found|does not exist|Unable to find') { 'site_not_in_recycle_bin' }
                elseif ($exMsg -match 'already exists') { 'site_already_active' }
                else { 'pnp_command_failed' }
        reason = $exMsg
        siteUrl = $siteUrl
        correlationId = $correlationId
    }
    return
} finally {
    try { Disconnect-PnPOnline -ErrorAction SilentlyContinue } catch {}
}

# === 4. Success ===
Send-Response -StatusCode 200 -Body @{
    ok = $true
    siteUrl = $siteUrl
    correlationId = $correlationId
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
}
