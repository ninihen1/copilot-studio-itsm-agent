# Phase 3.1 + capability expansion 2026-06-01 — Exchange Online PowerShell wrapper Function
#
# Wraps EXO cmdlets for the SP-IT-Exchange executor. Pure Graph cannot do these —
# see reference_graph_cannot_grant_exchange_fullaccess.md.
#
# Auth: cert-based app-only Connect-ExchangeOnline using SP-IT-Exchange Entra app.
# Cert PFX is stored in Key Vault `kv-itsm-demo`, secret name `SP-IT-Exchange-EXO-CertPfxBase64`,
# loaded at cold start via Managed Identity. The Function App's MI must have Get on the KV secret.
#
# Request shape (POST):
#   {
#     "action": "grant" | "revoke" |                       // mailbox FullAccess (default accessRights)
#               "grantSendAs" | "revokeSendAs" |           // Send As (Add/Remove-RecipientPermission)
#               "grantSendOnBehalf" | "revokeSendOnBehalf" |  // Send on Behalf (Set-Mailbox -GrantSendOnBehalfTo)
#               "createDistributionList" |                  // New-DistributionGroup
#               "addDLMember" | "removeDLMember",           // Add/Remove-DistributionGroupMember
#     "mailboxUpn": "shared.mailbox@example.com",          // FullAccess/SendAs/SendOnBehalf
#     "delegateUpn": "delegate@example.com",               // FullAccess/SendAs/SendOnBehalf; DL member for addDLMember/removeDLMember
#     "accessRights": "FullAccess",                         // optional, default "FullAccess" (FullAccess actions only)
#     "autoMapping": true,                                  // optional, default true (grant FullAccess only)
#     "dlName": "All Engineering",                          // createDistributionList
#     "dlAlias": "all-engineering",                         // optional, EXO derives from dlName when omitted
#     "dlSmtp": "all-engineering@example.com",              // optional createDistributionList primary SMTP
#     "dlType": "Distribution",                             // optional, "Distribution" | "Security", default "Distribution"
#     "dlIdentity": "all-engineering@example.com",          // addDLMember/removeDLMember (DL alias or SMTP)
#     "correlationId": "<ulid>"                             // optional, echoed in response
#   }
#
# Response 200:
#   { "ok": true, "action": "...", <action-specific fields>, "correlationId": "..." }
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

$action        = [string]$body.action
$mailboxUpn    = [string]$body.mailboxUpn
$delegateUpn   = [string]$body.delegateUpn
$accessRights  = if ($body.accessRights) { [string]$body.accessRights } else { 'FullAccess' }
$autoMapping   = if ($null -ne $body.autoMapping) { [bool]$body.autoMapping } else { $true }
$dlName        = [string]$body.dlName
$dlAlias       = [string]$body.dlAlias
$dlSmtp        = [string]$body.dlSmtp
$dlType        = if ($body.dlType) { [string]$body.dlType } else { 'Distribution' }
$dlIdentity    = [string]$body.dlIdentity
$correlationId = if ($body.correlationId) { [string]$body.correlationId } else { [guid]::NewGuid().ToString() }

$validActions = @('grant','revoke','grantSendAs','revokeSendAs','grantSendOnBehalf','revokeSendOnBehalf','createDistributionList','addDLMember','removeDLMember')
if ($action -notin $validActions) {
    Send-Response -StatusCode 400 -Body @{ ok = $false; error = 'invalid_action'; reason = "action must be one of: $($validActions -join ', ')"; correlationId = $correlationId }
    return
}

# Per-action required-field validation
$needsMailboxDelegate = $action -in @('grant','revoke','grantSendAs','revokeSendAs','grantSendOnBehalf','revokeSendOnBehalf')
if ($needsMailboxDelegate -and (-not $mailboxUpn -or -not $delegateUpn)) {
    Send-Response -StatusCode 400 -Body @{ ok = $false; error = 'missing_field'; reason = 'mailboxUpn and delegateUpn are required'; correlationId = $correlationId }
    return
}
if ($action -eq 'createDistributionList' -and -not $dlName) {
    Send-Response -StatusCode 400 -Body @{ ok = $false; error = 'missing_field'; reason = 'dlName is required for createDistributionList'; correlationId = $correlationId }
    return
}
if ($action -in @('addDLMember','removeDLMember') -and (-not $dlIdentity -or -not $delegateUpn)) {
    Send-Response -StatusCode 400 -Body @{ ok = $false; error = 'missing_field'; reason = 'dlIdentity and delegateUpn (member) are required for DL member changes'; correlationId = $correlationId }
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

# === 3. Perform the action ===
try {
    switch ($action) {
        'grant' {
            $result = Add-MailboxPermission -Identity $mailboxUpn -User $delegateUpn -AccessRights $accessRights -InheritanceType All -AutoMapping:$autoMapping -Confirm:$false -ErrorAction Stop
        }
        'revoke' {
            $result = Remove-MailboxPermission -Identity $mailboxUpn -User $delegateUpn -AccessRights $accessRights -InheritanceType All -Confirm:$false -ErrorAction Stop
        }
        'grantSendAs' {
            $result = Add-RecipientPermission -Identity $mailboxUpn -Trustee $delegateUpn -AccessRights SendAs -Confirm:$false -ErrorAction Stop
        }
        'revokeSendAs' {
            $result = Remove-RecipientPermission -Identity $mailboxUpn -Trustee $delegateUpn -AccessRights SendAs -Confirm:$false -ErrorAction Stop
        }
        'grantSendOnBehalf' {
            $result = Set-Mailbox -Identity $mailboxUpn -GrantSendOnBehalfTo @{ Add = $delegateUpn } -Confirm:$false -ErrorAction Stop
        }
        'revokeSendOnBehalf' {
            $result = Set-Mailbox -Identity $mailboxUpn -GrantSendOnBehalfTo @{ Remove = $delegateUpn } -Confirm:$false -ErrorAction Stop
        }
        'createDistributionList' {
            $dlParams = @{ Name = $dlName; Type = $dlType; Confirm = $false; ErrorAction = 'Stop' }
            if ($dlAlias) { $dlParams.Alias = $dlAlias }
            if ($dlSmtp)  { $dlParams.PrimarySmtpAddress = $dlSmtp }
            $result = New-DistributionGroup @dlParams
        }
        'addDLMember' {
            $result = Add-DistributionGroupMember -Identity $dlIdentity -Member $delegateUpn -BypassSecurityGroupManagerCheck -Confirm:$false -ErrorAction Stop
        }
        'removeDLMember' {
            $result = Remove-DistributionGroupMember -Identity $dlIdentity -Member $delegateUpn -BypassSecurityGroupManagerCheck -Confirm:$false -ErrorAction Stop
        }
    }
} catch {
    $exMsg = $_.Exception.Message
    Send-Response -StatusCode 500 -Body @{
        ok = $false
        error = if ($exMsg -match 'is already a delegate|already has|already a member') { 'already_present' }
                elseif ($exMsg -match 'is not a delegate|not a member|wasn''t found as a member') { 'not_present' }
                elseif ($exMsg -match 'couldn''t be found|can''t be found') { 'recipient_not_found' }
                elseif ($exMsg -match 'already exists') { 'already_exists' }
                else { 'exo_command_failed' }
        reason = $exMsg
        action = $action
        mailbox = $mailboxUpn
        delegate = $delegateUpn
        dlIdentity = $dlIdentity
        correlationId = $correlationId
    }
    return
} finally {
    try { Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue | Out-Null } catch {}
}

# === 4. Success ===
$resp = @{
    ok = $true
    action = $action
    correlationId = $correlationId
    completedAt = (Get-Date).ToUniversalTime().ToString('o')
}
if ($mailboxUpn)  { $resp.mailbox = $mailboxUpn }
if ($delegateUpn) { $resp.delegate = $delegateUpn }
if ($dlName)      { $resp.dlName = $dlName }
if ($dlIdentity)  { $resp.dlIdentity = $dlIdentity }
if ($action -in @('grant','revoke')) { $resp.accessRights = $accessRights; $resp.autoMapping = $autoMapping }
Send-Response -StatusCode 200 -Body $resp
