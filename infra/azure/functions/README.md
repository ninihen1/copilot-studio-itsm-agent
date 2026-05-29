# Azure Functions — `func-itsm-dev`

PowerShell-based Function App. Hosts Phase 3.1 wrappers for capabilities that have no Graph
equivalent.

## Functions

| Function | Trigger | Purpose |
|---|---|---|
| `exo-mailbox-permission` | HTTP POST | Grant / revoke Exchange Full Access via Connect-ExchangeOnline. Pure Graph cannot do this — see `memory/reference_graph_cannot_grant_exchange_fullaccess.md`. |
| _planned_ `jwt-sign` / `jwt-validate` | HTTP POST | Phase 2 backlog #1+#2. Not part of 3.1. |

## File layout

```
infra/azure/functions/
├── host.json                          # Function App config
├── profile.ps1                        # Cold-start hook — loads EXO cert from KV via MI
├── requirements.psd1                  # Az.Accounts, Az.KeyVault, ExchangeOnlineManagement
└── exo-mailbox-permission/
    ├── function.json                  # HTTP trigger binding
    └── run.ps1                        # the actual logic
```

## Deploy

```powershell
# 1. (One-time) Provision Function App + storage. Uses the existing rg-itsm-pilot RG.
$rg = 'rg-itsm-pilot'
$loc = 'australiaeast'
$saName = 'stitsmfunc' + (Get-Random -Min 1000 -Max 9999)
$appName = 'func-itsm-dev'

az storage account create --name $saName --resource-group $rg --location $loc --sku Standard_LRS
az functionapp create `
    --name $appName `
    --resource-group $rg `
    --storage-account $saName `
    --runtime powershell `
    --runtime-version 7.4 `
    --functions-version 4 `
    --consumption-plan-location $loc `
    --os-type Linux

# 2. Enable system-assigned managed identity
az functionapp identity assign --name $appName --resource-group $rg

# 3. Grant the MI access to KV secrets
$miPid = az functionapp identity show --name $appName --resource-group $rg --query principalId -o tsv
az role assignment create `
    --assignee-object-id $miPid `
    --assignee-principal-type ServicePrincipal `
    --role 'Key Vault Secrets User' `
    --scope "$(az keyvault show --name kv-itsm-demo --query id -o tsv)"

# 4. Set required app settings
az functionapp config appsettings set --name $appName --resource-group $rg --settings `
    ITSM_KEY_VAULT_NAME=kv-itsm-demo `
    ITSM_TENANT_DOMAIN=contoso.onmicrosoft.com `
    SP_IT_EXCHANGE_APPID=<from provision-5-executors output> `
    EXO_CERT_SECRET_NAME=SP-IT-Exchange-EXO-CertPfxBase64 `
    EXO_CERT_PASSWORD_NAME=SP-IT-Exchange-EXO-CertPassword

# 5. Generate + upload EXO cert
cd "c:\Users\ninih\GitHub\Copilot Studio\infra\azure"
./setup-exo-cert.ps1 -AppId <SP-IT-Exchange-AppId> -KeyVaultName kv-itsm-demo
# Follow the printed instructions to grant Exchange.ManageAsApp permission.

# 6. Deploy the Function App content
cd "c:\Users\ninih\GitHub\Copilot Studio\infra\azure\functions"
func azure functionapp publish $appName  # requires Azure Functions Core Tools v4

# 7. Get the Function key and store in KV (the executor flow reads it from there)
$key = az functionapp keys list --name $appName --resource-group $rg --query 'functionKeys.default' -o tsv
az keyvault secret set --vault-name kv-itsm-demo --name 'ExoMailboxPermission-FunctionKey' --value $key
```

## Smoke test

```powershell
$url = "https://func-itsm-dev.azurewebsites.net/api/exo-mailbox-permission?code=$key"
$body = @{
    action = 'grant'
    mailboxUpn = 'shared.mailbox@contoso.onmicrosoft.com'
    delegateUpn = 'arwen@contoso.onmicrosoft.com'
} | ConvertTo-Json
Invoke-RestMethod -Method POST -Uri $url -ContentType 'application/json' -Body $body
# Expect: { ok = $true, action = 'grant', mailbox = '...', delegate = '...', ... }
```

## Cost

- Consumption tier; ~$0.20 per 1M executions.
- Cold start ~3-5 seconds (PowerShell + EXO module is heavy). For pilot volumes (a few mailbox
  permission grants per week), cold-start is fine. If usage scales, switch to Premium tier.

## Cert rotation

Cert valid for 1 year from `setup-exo-cert.ps1` run. Rotate annually.

```powershell
./setup-exo-cert.ps1 -AppId <appid> -KeyVaultName kv-itsm-demo -RotateOnly
# Then restart the Function App to pick up the new cert at next cold start
az functionapp restart --name func-itsm-dev --resource-group rg-itsm-pilot
```

Phase 2 backlog #20 (rotation reminder flow) should fire 14/7/1 days before expiry.

## Why this is a Function and not a flow

PA flows can't run arbitrary PowerShell, can't load the ExchangeOnlineManagement module, and
can't do cert-based auth to EXO. The Function App is the smallest production-safe surface.

When/if Microsoft ships a Graph endpoint for `Add-MailboxPermission`, we delete this Function
and switch the Exchange executor back to a direct Graph call.
