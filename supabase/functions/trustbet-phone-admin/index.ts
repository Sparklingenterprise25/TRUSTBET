import { createClient } from "npm:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function reply(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return reply({ error: "Method not allowed." }, 405);

  const token = req.headers.get("Authorization")?.replace(/^Bearer\s+/i, "");
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!token || !url || !serviceKey) return reply({ error: "Unauthorized or server configuration missing." }, 401);

  const admin = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const { data: authData, error: authError } = await admin.auth.getUser(token);
  if (authError || !authData.user) return reply({ error: "Your session is invalid. Please sign in again." }, 401);

  const { data: caller, error: callerError } = await admin
    .from("profiles").select("role").eq("id", authData.user.id).maybeSingle();
  const owner = authData.user.email?.toLowerCase() === "superhybridservices@gmail.com"
    && !!authData.user.email_confirmed_at;
  if (callerError || (caller?.role !== "admin" && !owner)) return reply({ error: "Admin access required." }, 403);

  let body: { action?: string; userId?: string };
  try { body = await req.json(); } catch { return reply({ error: "Invalid request body." }, 400); }

  if (body.action === "list") {
    const { data, error } = await admin.from("profiles")
      .select("id,email,phone,full_name,created_at,account_approval_status,account_approval_requested_at,welcome_bonus_credited")
      .not("phone", "is", null)
      .order("account_approval_requested_at", { ascending: false });
    if (error) return reply({ error: error.message }, 500);
    return reply({ accounts: data || [] });
  }

  const id = body.userId || "";
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(id)) {
    return reply({ error: "A valid account ID is required." }, 400);
  }

  if (body.action === "approve") {
    const { data: result, error } = await admin.rpc("trustbet_admin_approve_phone_account", { p_user_id: id });
    if (error) return reply({ error: error.message }, 400);
    const { data: target, error: targetError } = await admin.auth.admin.getUserById(id);
    if (targetError || !target.user) return reply({ error: "Approval recorded, but Auth account could not be confirmed. Contact support." }, 500);
    const { error: authUpdateError } = await admin.auth.admin.updateUserById(id, {
      phone_confirm: true,
      ban_duration: "none",
    });
    if (authUpdateError) return reply({ error: "Approval recorded, but login activation failed: " + authUpdateError.message }, 500);
    return reply({ success: true, result });
  }

  if (body.action === "reject") {
    const { error } = await admin.rpc("trustbet_admin_reject_phone_account", { p_user_id: id });
    if (error) return reply({ error: error.message }, 400);
    const { error: banError } = await admin.auth.admin.updateUserById(id, { ban_duration: "876000h" });
    if (banError) return reply({ error: "Account rejected, but login blocking failed: " + banError.message }, 500);
    return reply({ success: true });
  }

  return reply({ error: "Unsupported action." }, 400);
});
