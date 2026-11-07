import { createClient } from "npm:@supabase/supabase-js@2";
import { PORTAL_HTML } from "./portal-html.ts";

const ALLOWED_ORIGINS = new Set([
  "https://trustbet-eta.vercel.app",
  "https://trustbet-git-security-admin-ui-isolation-sparklingenterprise25.vercel.app",
  "https://trustbet-15t1zxemr-sparklingenterprise25.vercel.app",
]);

function corsHeaders(origin: string | null) {
  const allowedOrigin = origin && ALLOWED_ORIGINS.has(origin) ? origin : "null";
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Headers": "authorization, apikey, x-client-info, content-type, x-trustbet-refresh-token",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Vary": "Origin",
    "Cache-Control": "no-store, max-age=0",
    "Pragma": "no-cache",
  };
}

function respond(body: unknown, status: number, origin: string | null) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders(origin), "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  const origin = req.headers.get("Origin");
  if (req.method === "OPTIONS") {
    if (!origin || !ALLOWED_ORIGINS.has(origin)) {
      return new Response("Origin not allowed.", { status: 403, headers: corsHeaders(origin) });
    }
    return new Response(null, { status: 204, headers: corsHeaders(origin) });
  }

  if (origin && !ALLOWED_ORIGINS.has(origin)) {
    return respond({ error: "Origin not allowed." }, 403, origin);
  }
  if (req.method !== "GET") {
    return respond({ error: "Method not allowed." }, 405, origin);
  }

  const authorization = req.headers.get("Authorization");
  const token = authorization?.match(/^Bearer\s+(.+)$/i)?.[1];
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const namedKeys = Deno.env.get("SUPABASE_PUBLISHABLE_KEYS");
  let defaultPublishableKey = "";
  if (namedKeys) {
    try {
      const parsed = JSON.parse(namedKeys) as Record<string, string>;
      const defaultKeyName = parsed.default;
      if (defaultKeyName) defaultPublishableKey = Deno.env.get(defaultKeyName) ?? "";
    } catch {
      console.error("Could not read configured Supabase publishable key names.");
    }
  }
  const publishableKey = Deno.env.get("SUPABASE_PUBLISHABLE_KEY")
    ?? Deno.env.get("SUPABASE_ANON_KEY")
    ?? defaultPublishableKey;

  if (!token || !supabaseUrl || !publishableKey) {
    return respond({ error: "Authentication required." }, 401, origin);
  }

  try {
    // Use the caller's JWT and publishable key. No service-role key or privileged
    // database client is needed to verify the caller's own profile role.
    const supabase = createClient(supabaseUrl, publishableKey, {
      auth: { autoRefreshToken: false, persistSession: false },
      global: { headers: { Authorization: `Bearer ${token}` } },
    });

    const { data: { user }, error: authError } = await supabase.auth.getUser(token);
    if (authError || !user) {
      return respond({ error: "Your session is invalid. Please sign in again." }, 401, origin);
    }

    const { data: profile, error: profileError } = await supabase
      .from("profiles")
      .select("role")
      .eq("id", user.id)
      .maybeSingle();

    if (profileError) {
      console.error("Admin portal role verification failed:", profileError.message);
      return respond({ error: "Could not verify admin access." }, 503, origin);
    }

    if (profile?.role !== "admin") {
      return respond({ error: "Admin access required." }, 403, origin);
    }

    // The protected document is loaded only after this request has passed both Auth and profile-role checks.
    const portalOrigin = origin && ALLOWED_ORIGINS.has(origin) ? origin : "https://trustbet-eta.vercel.app";
    const refreshToken = req.headers.get("x-trustbet-refresh-token") ?? "";
    if (!refreshToken) return respond({ error: "Your session could not be transferred to the secure portal. Please sign in again." }, 401, origin);
    const bootstrap = JSON.stringify({ access_token: token, refresh_token: refreshToken }).replace(/</g, "\\u003c");
    const portalHtml = PORTAL_HTML
      .replace("from'./supabase.js';", `from'${portalOrigin}/supabase.js';`)
      .replace('<script type="module">', `<script>window.__TRUSTBET_BOOTSTRAP_SESSION__=${bootstrap};</script><script type="module">`);
    return respond({ authorized: true, portalHtml }, 200, origin);
  } catch (error) {
    console.error("Admin portal authentication failed:", error);
    return respond({ error: "Unable to verify admin access." }, 500, origin);
  }
});
