# Phase 3.1 fix #5 — Exchange Online PowerShell wrapper Function
#
# Wraps Add-MailboxPermission / Remove-MailboxPermission for the SP-IT-Exchange executor.
# Pure Graph cannot grant Exchange Full Access — see reference_graph_cannot_grant_exchange_fullaccess.md.
#
# Auth: cert-based app-only Connect-ExchangeOnline using SP-IT-Exchange Entra app.
# Cert PFX is stored in Key Vault `kv-itsm-demo`, secret name `SP-IT-Exchange-EXO-CertPfxBase64`,
# loaded at cold start via Managed Identity. The Function App's MI must have Get on the KV secret.
#
# Request shape (POST):
#   {
#     "action": "grant" | "revoke",
#     "mailboxUpn": "shared.mailbox@example.com",
#     "delegateUpn": "delegate@example.com",
#     "accessRights": "FullAccess",         // optional, default "FullAccess"
#     "autoMapping": true,                   // optional, default true (only for grant)
#     "correlationId": "<ulid>"              // optional, echoed in response
#   }
#
# Response 200:
#   { "ok": true, "action": "grant", "mailbox": "...", "delegate": "...", "correlationId": "..." }
#
# Response 4xx/5xx:
#   { "ok": false, "error": "<code>", "reason": "<message>", "correlationId": "..." }

using namespace System.Net

param($Request, $TriggerMetadata)

$ErrorActionPreference = 'Stop'

$moduleRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'Modules'
if (Test-Path $moduleRoot) {
    $env:PSModulePath = "$moduleRoot$([System.IO.Path]::PathSeparator)$env:PSModulePath"
}

Import-Module Az.Accounts -ErrorAction Stop
Import-Module Az.KeyVault -ErrorAction Stop
Import-Module ExchangeOnlineManagement -ErrorAction Stop

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

$action       = [string]$body.action
$mailboxUpn   = [string]$body.mailboxUpn
$delegateUpn  = [string]$body.delegateUpn
$accessRights = if ($body.accessRights) { [string]$body.accessRights } else { 'FullAccess' }
$autoMapping  = if ($null -ne $body.autoMapping) { [bool]$body.autoMapping } else { $true }
$correlationId = if ($body.correlationId) { [string]$body.correlationId } else { [guid]::NewGuid().ToString() }

if ($action -notin @('grant','revoke')) {
    Send-Response -StatusCode 400 -Body @{ ok = $false; error = 'invalid_action'; reason = "action must be 'grant' or 'revoke'"; correlationId = $correlationId }
    return
}
if (-not $mailboxUpn -or -not $delegateUpn) {
    Send-Response -StatusCode 400 -Body @{ ok = $false; error = 'missing_field'; reason = 'mailboxUpn and delegateUpn are required'; correlationId = $correlationId }
    return
}

# === 2. Load EXO module + connect with cert-based app-only auth ===
# Try profile.ps1 cache first; if missing, load cert inline (resilient to profile.ps1 not running on every cold start).
if (-not $script:ExoCert) {
    try {
        $kvName = $env:ITSM_KEY_VAULT_NAME
        $certSecret = if ($env:EXO_CERT_SECRET_NAME) { $env:EXO_CERT_SECRET_NAME } else { 'SP-IT-Exchange-EXO-CertPfxBase64' }
        $pwdSecret  = if ($env:EXO_CERT_PASSWORD_NAME) { $env:EXO_CERT_PASSWORD_NAME } else { 'SP-IT-Exchange-EXO-CertPassword' }
        if (-not $kvName) {
            Send-Response -StatusCode 500 -Body @{ ok = $false; error = 'missing_env'; reason = 'ITSM_KEY_VAULT_NAME env var not set'; correlationId = $correlationId }
            return
        }
        Disable-AzContextAutosave -Scope Process | Out-Null
        Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
        $pfxB64 = (Get-AzKeyVaultSecret -VaultName $kvName -Name $certSecret -AsPlainText)
        $pfxPwd = (Get-AzKeyVaultSecret -VaultName $kvName -Name $pwdSecret  -AsPlainText)
        $pfxBytes = [Convert]::FromBase64String($pfxB64)
        $securePwd = ConvertTo-SecureString -String $pfxPwd -AsPlainText -Force
        $script:ExoCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
            $pfxBytes,
            $securePwd,
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
        )
    } catch {
        Send-Response -StatusCode 503 -Body @{ ok = $false; error = 'cert_load_failed'; reason = $_.Exception.Message; correlationId = $correlationId }
        return
    }
}

$tenantDomain = $env:ITSM_TENANT_DOMAIN  # e.g., 'contoso.onmicrosoft.com'
$appId        = $env:SP_IT_EXCHANGE_APPID
if (-not $tenantDomain -or -not $appId) {
    Send-Response -StatusCode 500 -Body @{ ok = $false; error = 'missing_env'; reason = 'ITSM_TENANT_DOMAIN and SP_IT_EXCHANGE_APPID env vars must be set on the Function App'; correlationId = $correlationId }
    return
}

try {
    Connect-ExchangeOnline `
        -Certificate    $script:ExoCert `
        -AppId          $appId `
        -Organization   $tenantDomain `
        -ShowBanner:$false `
        -ShowProgress:$false `
        -ErrorAction    Stop | Out-Null
} catch {
    Send-Response -StatusCode 502 -Body @{ ok = $false; error = 'exo_connect_failed'; reason = $_.Exception.Message; correlationId = $correlationId }
    return
}

# === 3. Perform the permission change ===
try {
    if ($action -eq 'grant') {
        $result = Add-MailboxPermission `
            -Identity        $mailboxUpn `
            -User            $delegateUpn `
            -AccessRights    $accessRights `
            -InheritanceType All `
            -AutoMapping:    $autoMapping `
            -Confirm:$false `
            -ErrorAction     Stop
    } else {
        $result = Remove-MailboxPermission `
            -Identity        $mailboxUpn `
            -User            $delegateUpn `
            -AccessRights    $accessRights `
            -InheritanceType All `
            -Confirm:$false `
            -ErrorAction     Stop
    }
} catch {
    $exMsg = $_.Exception.Message
    Send-Response -StatusCode 500 -Body @{
        ok = $false
        error = if ($exMsg -match 'is already a delegate') { 'already_granted' }
                elseif ($exMsg -match 'is not a delegate')  { 'not_granted' }
                elseif ($exMsg -match 'couldn''t be found') { 'mailbox_not_found' }
                else                                          { 'exo_command_failed' }
        reason = $exMsg
        action = $action
        mailbox = $mailboxUpn
        delegate = $delegateUpn
        correlationId = $correlationId
    }
    return
} finally {
    try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
}

# === 4. Success ===
Send-Response -StatusCode 200 -Body @{
    ok = $true
    action = $action
    mailbox = $mailboxUpn
    delegate = $delegateUpn
    accessRights = $accessRights
    autoMapping = $autoMapping
    correlationId = $correlationId
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
}
