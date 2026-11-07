# TRUSTBET protected admin portal verification plan

Branch: `security/admin-ui-isolation`

Status: implementation staged; static checks and a Vercel preview build passed. The Supabase Edge Function is not deployed, and authenticated portal/browser behavior is not yet runtime-verified.

## Release boundary

The protected admin portal is not ready for release until the full checklist below passes. Work stays on this branch. The production website, database, administrator accounts/roles, grants, RPC definitions, and the 12 previously identified SECURITY DEFINER warnings remain out of scope.

## Authorization tests

Run against the Edge Function after its protected asset delivery is implemented:

| Caller / condition | Expected result |
|---|---|
| No bearer token | 401; no portal HTML |
| Malformed bearer token | 401; no portal HTML |
| Expired/revoked token | 401; no portal HTML |
| Authenticated ordinary customer | 403; no portal HTML |
| Authenticated admin profile | 200 JSON containing portal HTML |
| Missing profile row | 403; no portal HTML |
| Profile role lookup denied / unavailable | Fail-closed 5xx; no portal HTML |
| Disallowed Origin preflight | 403 |
| Disallowed Origin request | 403 |
| Unsupported HTTP method | 405 |

For every response, verify CORS is restricted to the exact approved TRUSTBET origin. Every response containing portal HTML must be JSON and include `Cache-Control: no-store, max-age=0` and `Pragma: no-cache`. Confirm no service-role key, access token, or other secret is embedded in the asset or response.

## Customer-site regression tests

Run on the customer website with both a normal customer account and an administrator account:

- Sign in, sign out, refresh, and session restoration.
- Home, games, odds display, bet placement, wallet, deposits, withdrawals, account/profile, support, privacy, self-exclusion, and account-deletion request.
- Customer deposit bank details and request submission still work; the admin bank editor is absent from the public page.
- Customer support chat retains its 1,000-character limit, customer sender labels, seven-day history behavior, attachment validation, signed URLs, realtime updates, and read-notice behavior.
- Customer account-deletion submission remains available to eligible customers and continues to refuse administrator accounts.
- Public odds still load without requiring the admin portal to be open.
- Customer registration still reads the active registration rule and preserves both registration paths.

## Admin-portal regression tests

Use an existing administrator account only; do not create or modify roles:

- Explicit admin entry control appears only for the existing admin role.
- Portal entry fetches the protected JSON using the current session token; token never appears in a URL.
- Portal displays the existing dashboard appearance, responsive layout, section ordering, labels, and controls.
- Game odds editor: load, edit, validate, save one game, refresh, and verify unsaved edits in other games are not discarded unexpectedly.
- Registration-rule controls and read-only previews.
- Self-exclusion, deposit, withdrawal, and account-deletion review queues; decision confirmation; receipt display; refresh behavior.
- User search/actions, welcome-name management, recovery-code workflows, and phone-registration approvals, including their cross-refresh behavior.
- Single/bulk wallet-credit workflows, confirmation, duplicate protection, and result messaging.
- Bank-detail editor saves while public bank details remain unchanged.
- Admin support inbox search, pagination, conversation selection, identity display, realtime updates, and shared chat replies/attachments.
- Admin chat retains its 2,000-character limit, administrator sender interpretation, and 365-day history behavior.
- Return-to-TRUSTBET action restores the customer site without losing or changing the Supabase session.

## Browser/document transport tests

The authenticated fetch followed by a same-origin `iframe` using `srcdoc` is a critical, unproven integration point. Verify in supported browsers:

1. The JSON response is read only after successful authorization.
2. The `srcdoc` iframe executes the portal's module script and initializes styles and event handlers correctly.
3. The existing Supabase session is still available after replacement.
4. A failed fetch leaves the original customer page intact and displays a clear error.
5. The `BACK TO TRUSTBET` action returns the top-level page to the customer application and preserves the existing session.
6. Browser back/forward, refresh, and direct reload behavior do not reveal cached portal content to a non-admin user.
7. No portal asset is available through Vercel public static hosting, public storage, or an unauthenticated URL.

If document replacement proves unreliable, stop and revise the transport design rather than weakening the authorization boundary.

## Checks completed so far

- `node --check` passed for the public page's module script.
- `node --check` passed for the protected portal's module script extracted from the TypeScript asset constant.
- `deno check --no-lock supabase/functions/admin-portal/index.ts` passed.
- A static scan found no unresolved literal `$('<id>')` references in the public document.
- The public document contains no `#adminArea` dashboard root and no references to the extracted admin queues, bulk wallet-credit RPC, odds editor, registration admin panel, bank editor, or receipt overlay.
- Vercel preview deployment for the branch reached `READY`; fetching its root returned HTTP 200, the TRUSTBET page title, customer support markup, and customer account-deletion request markup, with no admin dashboard root.
- These are static/build checks only. No authenticated admin interaction or customer account workflow has been exercised in a browser.

## Final go/no-go

Do not call the portal complete until:

- All seven admin workflow clusters have been moved out of the public customer bundle.
- Shared customer/admin behavior has been split and regression-tested.
- The Edge Function serves the protected asset only after validating the caller's JWT and exact existing profile role.
- Automated/static checks and the browser test matrix pass.
- A preview can be tested without changing the production deployment.
- The user has personally confirmed the preview behaves correctly.

A successful source diff or authorization-only function response is not proof that the complete portal works.
