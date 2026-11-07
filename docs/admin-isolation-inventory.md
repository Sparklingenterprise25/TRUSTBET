# TRUSTBET admin isolation: implementation inventory

Branch: `security/admin-ui-isolation`

This inventory is a safety checkpoint before moving code. It does not change application behavior, database objects, roles, policies, or deployment configuration.

## Confirmed current layout

- The customer site and admin dashboard are in one static `index.html` (263,725 characters at the time of inspection).
- The admin DOM begins at `<div id="adminArea" class="hidden">` and contains 87 identified element IDs.
- The page has one large `type="module"` script (about 2,752 lines).
- Admin visibility currently depends on the browser-side `isAdmin()` check (`profile?.role === 'admin'`). Hiding the element is not a security boundary.
- There is no `package.json`, `vercel.json`, or Supabase `config.toml` in the repository root/current branch. The site is presently a static frontend.

## Admin-only areas identified

The following code is strongly admin-specific and is a candidate for the protected portal bundle:

- Game-odds editor and save/refresh controls (`loadGameOdds`, `renderAdminOddsEditor`, `saveAdminGameOdds`).
- Deposit and withdrawal review queues and decisions.
- Self-exclusion and account-deletion request review.
- User administration, account actions, welcome-name editing, recovery-code administration, and phone-registration approvals.
- Administrator wallet-credit workflows.
- Registration-rule controls and administrator-only previews.
- Administrator support inbox, search, pagination, and inbox realtime subscription.

The dashboard markup includes 87 IDs; examples include `adminGameOddsEditor`, `adminDeposits`, `adminWithdrawals`, `adminUsers`, `adminInbox`, and registration-rule controls.

## Shared code that must not be removed with the dashboard

Static inspection found administrator/customer behavior mixed into shared functions and UI:

- `profileLoad` controls account initialization, customer navigation, and admin startup.
- `isAdmin` is used for both UI gating and role-dependent behavior.
- `loadGameOdds` supplies public game odds and also refreshes the admin odds editor.
- Support chat shares a single chat panel, message renderer, realtime channel, and sender behavior; only the admin inbox and some admin-specific identity/retention behavior are exclusive.
- Deposit/wallet pages share customer controls with an administrator-only bank-details editor.
- Registration flows share public customer registration UI with admin-only registration-rule controls.
- Customer account deletion and administrator review are separate paths in shared logic.

These shared paths are the main regression risk. They need explicit separation points and tests rather than broad text deletion.

## Safe migration sequence (no deployment)

1. Extract admin-only markup and styles into a dedicated portal response that is returned only after server-side authentication and role verification. The authorization gate must validate the current user token and query that user's existing `profiles.role`; it must fail closed.
2. Extract admin-only event handlers and workflows into a protected module. Keep shared services in the public app only where they are genuinely required by customer workflows. Do not expose admin-only actions or privileged data in the public module.
3. Remove the admin DOM and admin-exclusive code from the public page. Retain public odds loading, customer support chat, customer registration, wallet/deposit/withdrawal requests, and customer account workflows.
4. Run static checks and browser-level regression/security tests before considering the branch ready.

## Non-negotiable preservation constraints

- Do not change admin roles, existing administrator accounts, permissions, customer records, or existing workflows.
- Do not change database schema, RLS policies, RPC grants/definitions, or Edge Functions that are already in use as part of this isolation task.
- Leave all 12 identified Supabase Security Advisor warnings involving authenticated access to SECURITY DEFINER functions untouched.
- Do not deploy to Vercel or Supabase as part of this work unless separately requested.
- Do not merge this branch into the production branch without approval.

## Validation required before completion

- Ordinary visitor: public site renders and customer workflows still operate.
- Customer account: can access only customer functionality; direct requests to the portal and admin-only endpoints fail closed.
- Administrator account: existing admin role is recognized and existing admin workflows remain functional.
- Source inspection of the public page and its unprotected assets: no admin dashboard markup or admin-exclusive handlers are delivered.
- Confirm existing styles/layout and public page behavior are unchanged.
- Verify that no database objects, permissions, or the 12 protected Security Advisor warnings were modified.

## Current limitation

The Edge Function source now returns the protected portal document only after JWT validation and exact `profiles.role === 'admin'` verification. The public `index.html` has had the admin dashboard root and extracted admin workflows removed. Static checks and a Vercel preview build passed. The function has not been deployed, and authenticated portal behavior has not been tested in a browser; this inventory does not claim the full security fix is complete.


## Additional DOM-boundary inspection

A tag-nesting scan confirms the `adminArea` wrapper is a real, balanced container. It begins at byte offset 67,239 and closes at byte offset 78,513 in the current 263,725-character file. The wrapper contains the administrator dashboard sections and administrator inbox, but the customer support panel, customer self-exclusion form, privacy information, and customer account-deletion request are outside that wrapper. Those customer sections must remain in the public page.

The page also has administrator-only bank-detail editing markup (`#adminBankEditor`) outside `#adminArea`, inside the customer deposit page. That is a separate extraction point: the public deposit page must retain its customer-facing bank details and deposit request form, while the editor must move behind the protected portal.

The shared live-chat panel (`#chatPanel`) is outside `#adminArea` and is used by both customer and administrator conversations. It must not be moved wholesale. The administrator inbox and its conversation-selection behavior can be moved, while the shared message panel and customer chat entry point remain available to customers.

The receipt overlay (`#adminReceiptOverlay`) is also outside the dashboard wrapper and is populated by administrator deposit/withdrawal review code. Its markup is currently an empty placeholder; it should be created inside the authenticated admin portal at the point where review receipts are needed, not left as a public admin-specific placeholder.

This confirms that removing the `adminArea` block alone would not complete isolation: admin bank editing, admin receipt handling, and admin-specific branches inside shared chat/profile code also need deliberate treatment.
