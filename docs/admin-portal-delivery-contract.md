# TRUSTBET protected admin portal delivery contract

Branch: `security/admin-ui-isolation`

Status: extraction implementation staged on this branch. The public `index.html` no longer contains the admin dashboard markup or the extracted admin workflow clusters. A protected portal document is delivered by the role-gated Edge Function source. A Vercel preview is READY; the Edge Function has not been deployed, and no production deployment has occurred.

## Decision

Keep the protected portal delivery behind the existing Supabase Edge Function authorization gate, but do **not** make the function return a top-level `text/html` response. Supabase documents that HTML responses from Edge Functions are rewritten to `text/plain` unless a supported custom domain is used. The TRUSTBET function currently uses the standard `*.supabase.co` endpoint.

Instead, the eventual function response should be JSON containing the protected portal document as a string:

```json
{
  "portalHtml": "<!doctype html>..."
}
```

The portal HTML should be a separate static asset bundled with the `admin-portal` function. The function must read and return that asset only after the requester's access token has been validated and the requester's own existing `profiles.role` has been confirmed as exactly `admin`.

Supabase documents static-file bundling for Edge Functions through `static_files` in `supabase/config.toml`. Its current documentation also says static files cannot be deployed through the API deployment path and require a Docker-based CLI build. This is a future deployment constraint, not permission to deploy now.

## Current implementation checkpoint

- `supabase/functions/admin-portal/portal-html.ts` now contains a protected document snapshot derived from the backed-up website source, with a `BACK TO TRUSTBET` control added inside the admin dashboard.
- `supabase/functions/admin-portal/index.ts` imports that document and includes it in the JSON response only after `auth.getUser(token)` succeeds and the caller's own `profiles.role` is confirmed as exactly `admin`.
- The document is embedded as a TypeScript module constant rather than relying on `static_files` bundling. This avoids adding an unverified Supabase CLI/Docker asset-bundling dependency at this stage.
- The protected document is currently a full-site snapshot from the backed-up source, with the original dashboard and admin workflows retained inside it. It is returned only after server-side authorization. The public `index.html` now retains customer pages and shared customer workflows; the admin dashboard wrapper, admin queues, review handlers, user/recovery/phone workflows, wallet-credit console, registration controls, odds editor, admin inbox, bank editor, and their dedicated styles have been removed from that public document.
- The customer page now shows an `OPEN ADMIN PORTAL` control only for an already-loaded admin profile. An explicit click obtains the current session and requests the JSON document; on success it opens a full-viewport same-origin `iframe` via `srcdoc`. Failed requests leave the customer page intact.
- Static validation passed: public and protected JavaScript modules pass `node --check`; the Edge Function passes `deno check`; all literal `$('<id>')` references in the public document resolve to static IDs; the Vercel preview returned HTTP 200 and the expected customer page content.
- Still unverified: live Edge Function behavior and browser execution of the protected iframe. The preview origin is not on the Edge Function's exact production CORS allowlist, and the function has intentionally not been deployed to the live Supabase project. Do not treat this as a completed runtime test.
- No database, Supabase project configuration, production website, or deployed function has been changed.

## Request / response contract

1. The signed-in customer-facing app obtains the current session using the existing Supabase client.
2. Only when the user deliberately opens the admin portal does the browser call the Edge Function with:
   - `Authorization: Bearer <current access token>`
   - the existing Supabase publishable key in the `apikey` header
   - the exact production website origin in the browser request.
3. The Edge Function validates the token with Supabase Auth and reads only the caller's own `profiles.role` using that caller's JWT.
4. If the token is invalid or missing, return HTTP 401 and no portal content.
5. If the profile role is not exactly `admin`, return HTTP 403 and no portal content.
6. If role lookup fails, return a fail-closed server error and no portal content.
7. Only after successful authorization may the function read its bundled portal HTML asset and return it in a JSON response.
8. Every response containing portal content must include `Cache-Control: no-store, max-age=0` and `Pragma: no-cache`. Do not put the portal asset in a public Vercel static directory, public storage bucket, or unauthenticated URL.
9. The customer-facing app embeds the received trusted portal document in a full-viewport same-origin `iframe` using `srcdoc`. The `srcdoc` document inherits the embedding page's base URL and origin, so the existing relative Supabase client import and local session storage remain available. The portal's return control navigates the top-level page back to TRUSTBET. This avoids `document.write()` and keeps the customer document intact underneath the portal frame. The browser behavior still requires real preview testing before this transport is accepted.
10. A failed request must leave the customer page usable and show a clear access/session message. Never fall back to exposing a hidden dashboard in the public page.

## Browser-origin and CORS check

The Vercel project currently reports one verified production domain: `https://trustbet-eta.vercel.app`. That exact origin is already in the Edge Function's allowlist. Keep the allowlist exact; do not use wildcard origins. If a production domain changes, update and verify the allowlist before enabling portal access.

A normal top-level navigation cannot attach a Supabase Bearer token by itself. Therefore the public app must make the authenticated fetch first; do not put access tokens in query strings, URL fragments, HTML links, or browser history.

## Asset and deployment constraints

- Keep the portal document in the Edge Function's own asset directory, not in the public site's static root.
- Add a narrowly scoped `[functions.admin-portal]` static-file configuration only when the repository's Supabase configuration is intentionally introduced and reviewed.
- Confirm the CLI version and Docker-based static-file bundling behavior before any future deploy. Supabase's current documentation notes that static files are not included through the API deployment flag.
- Before release, test the function with an ordinary visitor token, a customer token, an existing admin token, an expired token, and a role-lookup failure. These authorization cases have not yet been runtime-tested. Confirm that only the admin case receives the document.
- Confirm the response is JSON (not `text/html`), has no-store headers, and contains no service-role or secret key.
- Keep the existing CORS allowlist restricted to the verified production origin. The branch preview origin is intentionally not allowed, so the preview cannot exercise the Edge Function until a separately approved deployment/testing arrangement exists.

## Integration boundary

The current page is a single static HTML document with one large module. The protected portal document will need the admin dashboard markup, admin-only styles, admin-only handlers, and any shared presentation/services it requires. The public page will keep customer-facing markup and customer workflows.

The shared boundaries recorded in `admin-isolation-inventory.md` and `admin-js-boundaries.md` remain binding:
- retain customer deposit details and request submission; move only bank-detail editing;
- retain customer support chat and shared message behavior; move the admin inbox and its admin-only controls;
- retain public odds loading; move only the admin odds editor and save behavior;
- retain customer account deletion and self-exclusion submission; move only admin review queues;
- retain customer registration; move only admin registration-rule controls;
- split admin startup out of shared profile initialization rather than moving the whole initializer.

The dependency/call-site map was reviewed before extraction. The public page was reduced cluster by cluster; remaining validation must now focus on full customer regression and authenticated admin browser behavior.

## Explicit non-goals

- No database schema, RLS policy, RPC grant/definition, or data changes.
- No changes to admin roles, accounts, role assignments, or permissions.
- No edits to any of the 12 identified SECURITY DEFINER functions or their grants.
- No Vercel or Supabase deployment.
- No merge to the production branch.

## References checked

- Supabase Edge Function development tips (HTML response restriction): https://supabase.com/docs/guides/functions/development-tips
- Supabase Edge Function limits (HTML custom-domain and static-file deployment constraints): https://supabase.com/docs/guides/functions/limits
- Supabase changelog: static files in Edge Functions: https://supabase.com/changelog/32815-add-static-files


## Admin entry and return path

The current dashboard is automatically shown as part of the signed-in app when `profile.role` is `admin`; there is no dedicated admin route or portal button today. The future public app should therefore:

- Keep the normal customer pages available to every signed-in customer, including administrators.
- Show a small `ADMIN PORTAL` entry control only when the already-loaded profile role is `admin`. This is a convenience/UI decision only; the Edge Function remains the actual access boundary.
- Do not call admin queues, admin inbox, recovery-code administration, or other admin workflows during the public `profileLoad` path.
- On an explicit click, perform the authenticated JSON fetch described above and open the protected portal in a full-viewport same-origin iframe.
- Provide a clear `BACK TO TRUSTBET` action in the protected portal. Returning must restore the ordinary customer site without losing or changing the user's existing Supabase session.
- Preserve the existing customer experience for administrator accounts; the admin portal is an additional area, not a replacement for customer wallet, games, account, deposit, or withdrawal pages.
