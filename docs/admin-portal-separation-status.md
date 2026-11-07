# TRUSTBET admin/customer separation — branch checkpoint

Branch: `security/admin-ui-isolation`

## Implemented in this branch

- The public customer document no longer contains the admin dashboard DOM, odds editor, review queues, user/recovery/phone administration controls, bulk wallet-credit controls, registration-rule controls, admin bank editor, or admin inbox handlers.
- The customer account page exposes only an admin entry button when the loaded profile role is `admin`. This is a convenience control, not the security boundary.
- Clicking the entry control requests the protected portal document with the current access token.
- `supabase/functions/admin-portal/index.ts` validates the access token with Supabase Auth, reads the caller's own `profiles.role`, and returns the portal document only for the exact `admin` role. Responses are JSON and carry no-store headers.
- The portal document is displayed as a full-screen, dedicated admin workspace. Its customer navigation and customer pages are hidden; the admin dashboard remains the visible workspace.
- The `admin-users`, `trustbet-phone-admin`, and `trustbet-recovery-admin` Edge Function sources perform server-side caller authentication and role checks before their service-role operations.

## Security boundary

The CSS that presents the dedicated admin workspace is not an authorization mechanism. The actual boundary is the server-side token validation and role check before portal HTML is returned. Hiding the entry button or changing browser-side JavaScript cannot grant access.

An ordinary customer may discover that an admin endpoint exists, but a request with that customer's own token must receive 403 and no portal document. A missing/invalid token must receive 401 and no portal document.

The protected portal HTML is not part of the public Vercel customer asset. The customer page source contains no admin dashboard markup or admin-only workflow handlers.

## Remaining release blockers

The protected portal still calls these administrative Postgres RPCs directly:

- `admin_update_trustbet_game_odds_for_game`
- `review_self_exclusion_request`
- `admin_issue_bulk_wallet_credit`
- `set_active_registration_rule`

Their authorization must be verified in the deployed SQL definitions (each must independently reject non-admin callers, including direct REST/RPC requests). The current repository branch does not provide enough evidence to certify those deployed definitions, and this task has not modified the database or its existing functions.

The full authenticated browser test matrix is also outstanding. In particular, test an ordinary customer token, an existing admin token, expired tokens, role lookup failures, portal rendering, all admin controls, and customer regressions. The current Vercel preview is SSO-protected, so a READY build alone is not proof of browser behavior.

## Source-visibility caveat

The GitHub repository `Sparklingenterprise25/TRUSTBET` is currently public. That means a determined person can inspect the protected portal source in the repository even though the deployed customer page does not deliver the portal HTML to ordinary users. Browser Developer Tools on the customer site will not reveal the protected HTML after a customer receives 401/403, but public GitHub source visibility is a separate exposure.

If the requirement includes keeping the admin implementation itself confidential from anyone outside the organization, the repository must be made private or the protected admin implementation must be moved to a private source repository. Neither change has been made because it can affect collaborators, Vercel Git integration, and deployment access.

## Explicitly unchanged

- `main` and the live TRUSTBET website.
- Production Vercel deployment.
- Supabase database schema, RLS, RPC definitions/grants, and existing administrator accounts/roles.
- The already-deployed shared Supabase Edge Function.
- Existing protected SECURITY DEFINER functions and warnings.

No production deployment or merge is authorized by this checkpoint.
