#Requires -Version 7.0

<#
.SYNOPSIS
Phase 3.1 fix #5 — generates a self-signed cert for SP-IT-Exchange Entra app, uploads the
public key to the app, and stores the PFX (base64) + password in Key Vault for the
exo-mailbox-permission Function to consume.

.DESCRIPTION
Why this is needed: Connect-ExchangeOnline app-only auth requires a CERTIFICATE, not a client
secret. Even though SP-IT-Exchange already has a client secret in KV (from provision-5-executors.ps1),
EXO PowerShell will reject it.

This script:
  1. Generates a self-signed cert valid for 1 year, RSA 2048
  2. Exports public part as DER and uploads to SP-IT-Exchange app's keyCredentials
  3. Exports the full PFX (private + public), base64-encodes, stores in KV as `SP-IT-Exchange-EXO-CertPfxBase64`
  4. Generates a strong PFX password and stores it in KV as `SP-IT-Exchange-EXO-CertPassword`
  5. Reminds you to add Office 365 Exchange Online (00000002-0000-0ff1-ce00-000000000000)
     application permission `Exchange.ManageAsApp` to SP-IT-Exchange and grant admin consent

Pre-requisites:
  - SP-IT-Exchange Entra app exists (run provision-5-executors.ps1 first)
  - You're signed in to az with contoso global admin
  - PowerShell `New-SelfSignedCertificate` available (Windows or PS7+ with PKI module)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$AppId,
    [string]$KeyVaultName = 'kv-itsm-demo',
    [string]$CertSubject = 'CN=ITSM-EXO-AppOnly',
    [int]$ValidYears = 1,
    [switch]$RotateOnly  # If set, just rolls the cert without prompting about Exchange.ManageAsApp permission
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command New-SelfSignedCertificate -ErrorAction SilentlyContinue)) {
    throw "New-SelfSignedCertificate not available. Run on Windows PowerShell 5.1+ or PowerShell 7 with the PKI module."
}

# === 1. Generate the cert ===
Write-Host "`n=== 1. Generating self-signed cert ===" -ForegroundColor Cyan
$notAfter = (Get-Date).AddYears($ValidYears)
$cert = New-SelfSignedCertificate `
    -Subject          $CertSubject `
    -CertStoreLocation 'cert:\CurrentUser\My' `
    -KeyExportPolicy   Exportable `
    -KeySpec           Signature `
    -KeyLength         2048 `
    -KeyAlgorithm      RSA `
    -HashAlgorithm     SHA256 `
    -NotAfter          $notAfter
Write-Host "  Thumbprint: $($cert.Thumbprint)"
Write-Host "  NotAfter:   $($cert.NotAfter)"

# === 2. Generate strong PFX password and store in KV ===
Write-Host "`n=== 2. Generating PFX password + storing in KV ===" -ForegroundColor Cyan
# PS 7 has no System.Web.Security.Membership; build our own 64-char password from a SHELL-SAFE
# charset (no `&` `|` `<` `>` `$` `"` `'` ` ` chars that break command-line parsing in az).
$charset = ([char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_')
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
$bytes = New-Object byte[] 64
$rng.GetBytes($bytes)
$pfxPwd = -join ($bytes | ForEach-Object { $charset[$_ % $charset.Length] })
$securePfxPwd = ConvertTo-SecureString -String $pfxPwd -AsPlainText -Force
az keyvault secret set --vault-name $KeyVaultName --name 'SP-IT-Exchange-EXO-CertPassword' --value $pfxPwd | Out-Null
Write-Host "  KV secret 'SP-IT-Exchange-EXO-CertPassword' set."

# === 3. Export PFX, base64-encode, store in KV ===
Write-Host "`n=== 3. Exporting PFX + storing in KV ===" -ForegroundColor Cyan
$pfxPath = Join-Path $env:TEMP "exo-cert-$(Get-Random).pfx"
Export-PfxCertificate -Cert $cert -FilePath $pfxPath -Password $securePfxPwd | Out-Null
$pfxBytes = [System.IO.File]::ReadAllBytes($pfxPath)
$pfxB64 = [Convert]::ToBase64String($pfxBytes)
az keyvault secret set --vault-name $KeyVaultName --name 'SP-IT-Exchange-EXO-CertPfxBase64' --value $pfxB64 | Out-Null
Remove-Item $pfxPath -Force
Write-Host "  KV secret 'SP-IT-Exchange-EXO-CertPfxBase64' set ($([math]::Round($pfxBytes.Length / 1024, 1)) KB)."

# === 4. Upload public cert to SP-IT-Exchange app keyCredentials ===
Write-Host "`n=== 4. Uploading public cert to Entra app $AppId ===" -ForegroundColor Cyan
$publicCertB64 = [Convert]::ToBase64String($cert.RawData)
$tempCer = Join-Path $env:TEMP "exo-public-$(Get-Random).cer"
[System.IO.File]::WriteAllBytes($tempCer, $cert.RawData)
az ad app credential reset `
    --id $AppId `
    --cert "@$tempCer" `
    --append `
    --years $ValidYears | Out-Null
Remove-Item $tempCer -Force
Write-Host "  Public cert uploaded to SP-IT-Exchange app keyCredentials."

# === 5. Reminder for Exchange.ManageAsApp permission ===
if (-not $RotateOnly) {
    Write-Host "`n=== 5. Manual step required ===" -ForegroundColor Yellow
    Write-Host "  Connect-ExchangeOnline app-only auth requires the Office 365 Exchange Online API"
    Write-Host "  Exchange.ManageAsApp application permission. The provision-5-executors.ps1 script"
    Write-Host "  granted Microsoft Graph permissions but NOT Exchange Online API permissions."
    Write-Host ""
    Write-Host "  Run this in a contoso global admin context:" -ForegroundColor White
    Write-Host ""
    Write-Host "    # The Office 365 Exchange Online resource has appId 00000002-0000-0ff1-ce00-000000000000"  -ForegroundColor DarkGray
    Write-Host "    # Exchange.ManageAsApp role id is 00000000-0000-4000-8000-000000000047"                   -ForegroundColor DarkGray
    Write-Host "    az ad app permission add --id $AppId ``" -ForegroundColor White
    Write-Host "        --api 00000002-0000-0ff1-ce00-000000000000 ``" -ForegroundColor White
    Write-Host "        --api-permissions 00000000-0000-4000-8000-000000000047=Role" -ForegroundColor White
    Write-Host "    az ad app permission admin-consent --id $AppId" -ForegroundColor White
    Write-Host ""
    Write-Host "  Verify with:" -ForegroundColor White
    Write-Host "    az ad sp show --id $AppId --query 'appRoles[?value==``Exchange.ManageAsApp``]'" -ForegroundColor DarkGray
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
Write-Host "  Cert thumbprint: $($cert.Thumbprint)"
Write-Host "  KV secrets:      SP-IT-Exchange-EXO-CertPfxBase64, SP-IT-Exchange-EXO-CertPassword"
Write-Host "  Function App:    set ITSM_KEY_VAULT_NAME, SP_IT_EXCHANGE_APPID, ITSM_TENANT_DOMAIN env vars"
Write-Host "  Schedule rotation reminder: $($notAfter.AddDays(-30).ToString('yyyy-MM-dd')) (30 days before expiry)" -ForegroundColor Yellow
