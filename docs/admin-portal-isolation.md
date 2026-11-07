# Admin portal isolation — implementation notes

## Authentication gate added

The branch adds the Supabase Edge Function source at
`supabase/functions/admin-portal/index.ts`.

When deployed with Supabase JWT verification enabled, the endpoint:

- Requires a valid Supabase access token.
- Resolves the user with `auth.getUser(token)`.
- Reads only that user's `profiles.role` using the caller's JWT.
- Authorizes only when the existing profile role is exactly `admin`.
- Fails closed on missing/invalid sessions and profile lookup errors.
- Uses no service-role key and makes no database, role, policy, grant, or function-permission changes.
- Sends no-store cache headers and restricts browser CORS to the current TRUSTBET Vercel origin.

Endpoint after deployment:
`GET https://gzhxsdwhrrphbrjcnytj.supabase.co/functions/v1/admin-portal`

Send the signed-in user's access token as `Authorization: Bearer <access_token>`.
Deploy with `verify_jwt: true`.

## Important: this is the authorization foundation, not the completed UI isolation

The current public `index.html` still contains the admin dashboard markup and a
large shared JavaScript module. Hiding the dashboard or calling this gate while
leaving that source in the public HTML would not meet the stated confidentiality
goal. The admin DOM and admin-only client code must be extracted into a separately
served protected portal response, with the role check performed before those
assets are returned. The public customer page must then be updated to remove the
admin markup and admin-only code without breaking shared customer workflows.

That extraction is deliberately not approximated here: the current admin code is
interleaved with customer code, and deleting its markup alone can break direct DOM
bindings. No production deployment or public-page change is included in this
foundation commit.

## Explicit scope protections

- Do not edit any of the 12 existing SECURITY DEFINER functions or their grants.
- Do not change admin roles, role assignments, or existing business permissions.
- Do not change production until the full protected portal extraction is reviewed
  and tested on this branch.
