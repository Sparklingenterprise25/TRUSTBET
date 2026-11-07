# TRUSTBET auth and recovery deployment notes

This branch is development-only. No migration or Edge Function in this branch has been applied to the production Supabase project.

## Required Supabase Auth configuration

After reviewing and applying the database migrations in a staging project, configure the Custom Access Token Hook:

- Hook type: Custom Access Token
- Function: `public.trustbet_access_token_gate`
- URI: `pg-functions://postgres/public/trustbet_access_token_gate`

This hook is required for server-side rejection of pending/rejected phone accounts and currently locked phone accounts. Without enabling it in Supabase Auth, the SQL function alone does not enforce the gate.

## Important plan limitation: progressive password lockout

Supabase's Password Verification Attempt hook is documented as available only on Teams and Enterprise plans. The requested progressive lockout (5 failures -> 15 minutes, next 5 -> 1 hour, next 5 -> 24 hours) cannot be safely enforced for every direct Supabase password-login request on the current Free plan using an Edge Function alone: clients can call the public Supabase Auth password endpoint directly and bypass an application-side proxy.

Do not describe the progressive lockout as complete until either:
1. the project has a Supabase plan that supports the Password Verification Attempt hook and the hook is configured; or
2. the authentication architecture is changed so phone password authentication cannot be performed directly against the public Auth endpoint.

The existing SQL failure-counter RPCs are groundwork only; they do not enforce this policy by themselves.

## Secrets required by recovery functions

Set these as Supabase Edge Function secrets only (never commit them):
- `TRUSTBET_RECOVERY_ENCRYPTION_KEY`: base64-encoded 32-byte random key for AES-GCM.
- `TRUSTBET_RECOVERY_HASH_PEPPER`: long random secret used when hashing recovery codes.

The admin recovery function must not be deployed until both secrets are configured. Rotate them only with a deliberate migration/rotation plan because existing encrypted codes depend on the encryption key.

## Safe release sequence

1. Review all SQL migrations and Edge Function code on this branch.
2. Apply migrations only to a separate staging project first.
3. Configure the Auth hook in staging.
4. Configure secrets and deploy Edge Functions to staging.
5. Test with dedicated test accounts only; never use real customer accounts.
6. Verify wallet balances, transaction records, email signup, phone approval, rejected login, code one-time use, and recovery reset.
7. Only after review and explicit approval should production changes be considered.

## Current status

- Development branch contains schema groundwork, phone approval RPCs, admin functions, and the access-token gate migration.
- The access-token gate is not active until its migration is applied and the Auth hook is configured.
- Recovery-code redemption now has a branch-only Edge Function (trustbet-recovery-reset) and SQL claim/finalize/release primitives. It supports password reset using the account phone number or email plus a one-time six-digit recovery code.
- Recovery redemption attempts are rate-limited to five attempts per account identifier per 15-minute window using a peppered identifier hash.
- The reset function requires TRUSTBET_RECOVERY_HASH_PEPPER; the existing admin code-issuance function additionally requires TRUSTBET_RECOVERY_ENCRYPTION_KEY.
- The frontend has not yet been connected to the reset function.
- Recovery redemption has not yet been tested against a staging database/Auth project. The SQL migration and Edge Function are not production-ready until those tests pass.
- Complete phone login lockout is not finished. The SQL failure-counter functions are groundwork only; the Free plan limitation described above remains.
- No production database or live website changes have been made.
