# Phase 3.1 — Function App profile.ps1
#
# Runs once per cold start. Loads the EXO cert from Key Vault into a script-scope variable
# that exo-mailbox-permission/run.ps1 reuses across invocations on the same instance.
#
# Required env vars:
#   ITSM_KEY_VAULT_NAME      — e.g., kv-itsm-demo
#   EXO_CERT_SECRET_NAME     — KV secret name holding base64-encoded PFX (default: SP-IT-Exchange-EXO-CertPfxBase64)
#   EXO_CERT_PASSWORD_NAME   — KV secret name holding the PFX password (default: SP-IT-Exchange-EXO-CertPassword)
#
# The Function App's system-assigned MI must have:
#   - Get on both KV secrets (RBAC: Key Vault Secrets User on the KV)

if ($env:MSI_ENDPOINT -or $env:IDENTITY_ENDPOINT) {
    $moduleRoot = Join-Path $PSScriptRoot 'Modules'
    if (Test-Path $moduleRoot) {
        $env:PSModulePath = "$moduleRoot$([System.IO.Path]::PathSeparator)$env:PSModulePath"
    }

    Import-Module Az.Accounts -ErrorAction Stop
    Import-Module Az.KeyVault -ErrorAction Stop

    try {
        Disable-AzContextAutosave -Scope Process | Out-Null
        $azContext = Connect-AzAccount -Identity -ErrorAction Stop
    } catch {
        Write-Warning "profile.ps1: Connect-AzAccount with MI failed: $($_.Exception.Message)"
        return
    }

    $kvName        = $env:ITSM_KEY_VAULT_NAME
    $certSecret    = if ($env:EXO_CERT_SECRET_NAME)   { $env:EXO_CERT_SECRET_NAME }   else { 'SP-IT-Exchange-EXO-CertPfxBase64' }
    $pwdSecret     = if ($env:EXO_CERT_PASSWORD_NAME) { $env:EXO_CERT_PASSWORD_NAME } else { 'SP-IT-Exchange-EXO-CertPassword' }

    if (-not $kvName) {
        Write-Warning "profile.ps1: ITSM_KEY_VAULT_NAME env var missing; skipping cert load."
        return
    }

    try {
        $pfxB64 = (Get-AzKeyVaultSecret -VaultName $kvName -Name $certSecret -AsPlainText)
        $pfxPwd = (Get-AzKeyVaultSecret -VaultName $kvName -Name $pwdSecret  -AsPlainText)
        $pfxBytes = [Convert]::FromBase64String($pfxB64)
        $securePwd = ConvertTo-SecureString -String $pfxPwd -AsPlainText -Force
        $script:ExoCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2(
            $pfxBytes,
            $securePwd,
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
        )
        Write-Host "profile.ps1: EXO cert loaded from KV $kvName/$certSecret (thumbprint=$($script:ExoCert.Thumbprint))"
    } catch {
        Write-Warning "profile.ps1: failed to load EXO cert: $($_.Exception.Message)"
    }
}
