# Executor Idempotency Pre-Check Patterns

Scope: six ITSM executor flows and their current job types  
Status: Design guidance for safe retries

## Why This Exists

Dispatcher-level idempotency prevents duplicate dispatch for the same idempotency key, but executor retries can still repeat non-idempotent downstream operations if a flow fails after the target system write and before the Provisioning Job audit row is updated.

Every executor should use this shape:

```text
Read Provisioning Job
Validate jobType prefix and current status
Read idempotency/audit state
Pre-check target state
If target already matches requested end state:
  mark Provisioning Job Succeeded with idempotent=true and no write
Else:
  perform write
  verify target state
  mark Provisioning Job Succeeded
```

## Shared Pre-Check Contract

Every executor should write a compact pre-check result into `ResultJson` or App Insights:

```json
{
  "idempotency": {
    "preCheck": "target_already_in_desired_state",
    "writeSkipped": true
  }
}
```

Recommended states:

| State | Meaning |
|---|---|
| `target_already_in_desired_state` | Safe to mark succeeded without write. |
| `target_missing` | Target does not exist; fail permanent unless job type creates it. |
| `target_conflict` | Target exists but differs from requested immutable fields. |
| `write_required` | Proceed with downstream write. |
| `verification_failed` | Write returned success but post-check did not confirm desired state. |

## Identity Executor

Job types:

- `identity.resetPassword`
- `identity.disableUser`
- `identity.enableUser`
- `identity.createUser`
- `identity.clearMfa`

| Job type | Pre-check | Skip condition | Write | Post-check |
|---|---|---|---|---|
| `identity.resetPassword` | Read user by UPN; verify account exists and is not protected. | No safe skip for password value because password hash cannot be compared. | Reset password. | Confirm Graph success and record request ID; optionally require user to change password at next sign-in. |
| `identity.disableUser` | GET `/users/{id}?$select=accountEnabled,userPrincipalName` | `accountEnabled=false` | PATCH `accountEnabled=false` | Re-read user and confirm disabled. |
| `identity.enableUser` | GET `/users/{id}?$select=accountEnabled,userPrincipalName` | `accountEnabled=true` | PATCH `accountEnabled=true` | Re-read user and confirm enabled. |
| `identity.createUser` | Lookup by UPN and immutable employee ID if available. | User exists with matching UPN and expected attributes. | POST `/users` | Re-read created user and record ID. |
| `identity.clearMfa` | List authentication methods. | No removable/resettable methods remain except required password method. | Delete/reset allowed auth methods. | Re-list methods and confirm desired method set. |

Special rules:

- Never automate protected admin or break-glass accounts without `ITSM-Admins` override.
- For `identity.resetPassword`, retries cannot prove whether the exact new password was already set. Prefer generating the password once, storing only a secure reference, and marking succeeded immediately after Graph success.

## Groups Executor

Job types:

- `groups.addMember`
- `groups.removeMember`

| Job type | Pre-check | Skip condition | Write | Post-check |
|---|---|---|---|---|
| `groups.addMember` | GET group member by user ID or list membership. | User is already a member. | POST member reference to group. | Re-check membership exists. |
| `groups.removeMember` | GET group member by user ID or list membership. | User is already not a member. | DELETE member reference from group. | Re-check membership absent. |

Special rules:

- Validate group is in `ManagedGroups` allow-list.
- Treat "object already exists" on add as success after membership verification.
- Treat "not found" on remove as success only if membership absence is verified.

## Licensing Executor

Job types:

- `licensing.assign`
- `licensing.revoke`

| Job type | Pre-check | Skip condition | Write | Post-check |
|---|---|---|---|---|
| `licensing.assign` | GET user `assignedLicenses`; check SKU availability. | User already has requested SKU. | POST `assignLicense` with addLicenses. | Re-read assigned licenses and confirm SKU present. |
| `licensing.revoke` | GET user `assignedLicenses`. | User does not have requested SKU. | POST `assignLicense` with removeLicenses. | Re-read assigned licenses and confirm SKU absent. |

Special rules:

- Validate SKU against `AllowedLicenseSkus`.
- Record SKU ID and display name in `ResultJson`.
- If license assignment fails due to dependency plan conflicts, fail permanent with clear error.

## Exchange Executor

Job types:

- `exchange.grantFullAccess`
- `exchange.revokeFullAccess`

These route through the EXO mailbox permission Function.

| Job type | Pre-check | Skip condition | Write | Post-check |
|---|---|---|---|---|
| `exchange.grantFullAccess` | Function or EXO query: check mailbox permissions for delegate. | Delegate already has FullAccess. | Invoke Function action `grant`. | Query permissions and confirm FullAccess present. |
| `exchange.revokeFullAccess` | Function or EXO query: check mailbox permissions for delegate. | Delegate does not have FullAccess. | Invoke Function action `revoke`. | Query permissions and confirm FullAccess absent. |

Special rules:

- Validate mailbox exists before grant/revoke.
- Validate delegate user exists.
- Require mailbox owner or policy approval.
- Function should return `alreadyInDesiredState=true` when it skips the write.

## SharePoint Executor

Current job type:

- `sharepoint.restoreFile`

Likely future job types:

- `sharepoint.grantAccess`
- `sharepoint.revokeAccess`

| Job type | Pre-check | Skip condition | Write | Post-check |
|---|---|---|---|---|
| `sharepoint.restoreFile` | Check requested site is allow-listed; check recycle bin item exists; check destination path/file existence. | File already exists at original/destination path with expected name and metadata. | Restore recycle bin item. | Confirm file exists at destination. |
| `sharepoint.grantAccess` | Check current permissions on target item/site. | Principal already has requested role. | Grant role. | Re-read permissions and confirm role present. |
| `sharepoint.revokeAccess` | Check current permissions on target item/site. | Principal does not have role. | Remove role assignment. | Re-read permissions and confirm role absent. |

Special rules:

- Reject sites not in the managed Sites.Selected allow-list.
- For restore, "recycle bin item not found" is not automatically success unless destination file exists and matches expected metadata.
- Record `siteUrl`, `itemId`, and destination URL in `ResultJson`.

## Teams Executor

Job types:

- `teams.createChannel`
- `teams.addChannelMember`

| Job type | Pre-check | Skip condition | Write | Post-check |
|---|---|---|---|---|
| `teams.createChannel` | Check team exists and is allow-listed; list channels by display name. | Channel with normalized requested name already exists in target team. | POST channel create. | Re-list/get channel and record channel ID. |
| `teams.addChannelMember` | Check team/channel allow-list; check user exists; check channel membership. | User is already a member. | POST channel member. | Re-check membership exists. |

Special rules:

- Normalize channel display names before duplicate checks.
- Decide whether duplicate display name with different membership/privacy settings is success or conflict.
- For private/shared channels, require owner approval and validate channel type before membership changes.

## ResultJson Examples

Skipped add-member because already member:

```json
{
  "ok": true,
  "idempotent": true,
  "preCheck": "target_already_in_desired_state",
  "writeSkipped": true,
  "target": {
    "groupId": "00000000-0000-0000-0000-000000000000",
    "userId": "00000000-0000-4000-8000-000000000003"
  }
}
```

Write performed:

```json
{
  "ok": true,
  "idempotent": false,
  "preCheck": "write_required",
  "writeSkipped": false,
  "graphRequestId": "request-id",
  "verified": true
}
```

## Flow Implementation Pattern

Recommended action names in each executor:

```text
Parse_Target_And_Args
Validate_JobType_Prefix
Check_Target_AllowList
PreCheck_Current_State
If_Already_Desired_State
  Patch_PJ_Succeeded_Idempotent
Else
  Execute_Write
  Verify_Post_State
  Patch_PJ_Succeeded
Catch_Permanent_Failure
Catch_Transient_Failure
```

## Testing Matrix

Each job type needs at least three tests:

| Test | Purpose |
|---|---|
| First execution | Confirms normal write succeeds. |
| Replay after success | Confirms pre-check skips duplicate write and marks success. |
| Opposite state | Confirms remove/revoke/disable operations treat already-absent or already-disabled as safe success where appropriate. |

For operations like `identity.resetPassword`, replay is not a no-op. The safer pattern is dispatcher/executor idempotency table short-circuit before another password reset is attempted.

## Implementation Priority

1. Add pre-checks for non-idempotent membership operations: `groups.addMember`, `teams.addChannelMember`.
2. Add license present/absent checks for `licensing.assign` and `licensing.revoke`.
3. Add Exchange permission present/absent checks in the EXO Function.
4. Add SharePoint restore destination/recycle-bin checks.
5. Add identity enable/disable current-state checks.
6. Treat `identity.resetPassword` as idempotency-table dependent and block replay before write.
