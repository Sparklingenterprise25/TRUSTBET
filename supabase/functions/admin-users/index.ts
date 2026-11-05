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

  try {
    const authHeader = req.headers.get("Authorization");
    const token = authHeader?.replace(/^Bearer\s+/i, "");
    const url = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!token || !url || !serviceKey) return reply({ error: "Unauthorized or server configuration missing." }, 401);

    const admin = createClient(url, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: authData, error: authError } = await admin.auth.getUser(token);
    if (authError || !authData.user) return reply({ error: "Your session is invalid. Please sign in again." }, 401);

    const { data: callerProfile, error: profileError } = await admin
      .from("profiles").select("role").eq("id", authData.user.id).maybeSingle();

    const isConfirmedOwner = authData.user.email?.toLowerCase() === "superhybridservices@gmail.com"
      && !!authData.user.email_confirmed_at;
    if (profileError) console.error("Admin profile lookup failed:", profileError.message);
    if (callerProfile?.role !== "admin" && !isConfirmedOwner) {
      return reply({ error: profileError ? "Could not verify admin access: " + profileError.message : "Admin access required." }, profileError ? 500 : 403);
    }

    let body: { action?: string; userId?: string; displayName?: string };
    try { body = await req.json(); } catch { return reply({ error: "Invalid request body." }, 400); }

    if (body.action === "list") {
      const users = [];
      for (let page = 1; page <= 100; page++) {
        const { data, error } = await admin.auth.admin.listUsers({ page, perPage: 1000 });
        if (error) return reply({ error: error.message }, 500);
        users.push(...data.users);
        if (data.users.length < 1000) break;
      }
      const { data: profiles, error } = await admin
        .from("profiles").select("id,email,role,full_name,created_at,phone,account_approval_status,dashboard_display_name");
      if (error) return reply({ error: error.message }, 500);
      const byId = new Map((profiles || []).map((p) => [p.id, p]));
      return reply({
        users: users.map((u) => ({
          id: u.id,
          email: u.email || "",
          created_at: u.created_at,
          last_sign_in_at: u.last_sign_in_at,
          banned_until: u.banned_until,
          profile: byId.get(u.id) || null,
        })),
      });
    }

    const targetId = body.userId;
    if (!targetId || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(targetId)) {
      return reply({ error: "A valid user ID is required." }, 400);
    }
    if (body.action === "set-welcome-name") {
      const { data: targetAuth, error: targetAuthError } = await admin.auth.admin.getUserById(targetId);
      if (targetAuthError) return reply({ error: targetAuthError.message }, 500);
      if (!targetAuth.user?.email) return reply({ error: "Welcome-name corrections are available only for email accounts." }, 400);
      const displayName = String(body.displayName ?? "").trim().replace(/\s+/g, " ").toUpperCase();
      if (displayName.length > 60 || !/^[A-Z]+(?: [A-Z]+)*$/.test(displayName)) {
        return reply({ error: "The welcome name must contain letters A–Z only, with single spaces between names, and be 60 characters or fewer." }, 400);
      }
      const { data: updated, error: updateError } = await admin
        .from("profiles")
        .update({ dashboard_display_name: displayName || null })
        .eq("id", targetId)
        .select("id,dashboard_display_name")
        .maybeSingle();
      if (updateError) return reply({ error: updateError.message }, 500);
      if (!updated) return reply({ error: "The user's profile could not be found." }, 404);
      return reply({ success: true, dashboard_display_name: updated.dashboard_display_name });
    }

    if (targetId === authData.user.id) return reply({ error: "You cannot manage your own admin account here." }, 400);
    if (targetId === "461892b7-f24b-4ba8-99d7-fa9bb44d1a33") return reply({ error: "The protected administrator account cannot be managed from the dashboard. Use Supabase manually." }, 403);

    const { data: targetProfile, error: targetProfileError } = await admin
      .from("profiles").select("role").eq("id", targetId).maybeSingle();
    if (targetProfileError) return reply({ error: targetProfileError.message }, 500);
    if (targetProfile?.role === "admin") return reply({ error: "Admin accounts are protected from ban and deletion." }, 403);

    if (body.action === "ban" || body.action === "unban") {
      const { error } = await admin.auth.admin.updateUserById(targetId, {
        ban_duration: body.action === "ban" ? "876000h" : "none",
      });
      if (error) return reply({ error: error.message }, 400);
      return reply({ success: true, action: body.action });
    }

    if (body.action !== "delete") return reply({ error: "Unsupported action." }, 400);

    // Read storage ownership through a narrowly granted RPC. The storage schema
    // is not exposed through PostgREST, so querying storage.objects directly fails.
    const { data: objects, error: storageError } = await admin.rpc(
      "admin_list_user_storage_objects",
      { p_user_id: targetId },
    );
    if (storageError) return reply({ error: "Could not safely check the user's stored files: " + storageError.message }, 500);

    const grouped = new Map<string, string[]>();
    for (const object of objects || []) {
      const paths = grouped.get(object.bucket_id) || [];
      paths.push(object.name);
      grouped.set(object.bucket_id, paths);
    }
    for (const [bucket, paths] of grouped) {
      const { error } = await admin.storage.from(bucket).remove(paths);
      if (error) return reply({ error: "Could not remove the user's stored files: " + error.message }, 500);
    }

    const { data: conversations, error: conversationsError } = await admin
      .from("support_conversations").select("id").eq("user_id", targetId);
    if (conversationsError) return reply({ error: conversationsError.message }, 500);
    const { error: authoredMessagesError } = await admin
      .from("support_messages").delete().eq("sender_id", targetId);
    if (authoredMessagesError) return reply({ error: authoredMessagesError.message }, 500);
    const conversationIds = (conversations || []).map((c) => c.id);
    if (conversationIds.length) {
      const { error } = await admin.from("support_conversations").delete().in("id", conversationIds);
      if (error) return reply({ error: error.message }, 500);
    }

    const cleanupSteps = [
      () => admin.from("demo_bets").delete().eq("user_id", targetId),
      () => admin.from("deposit_requests").update({ reviewed_by: null }).eq("reviewed_by", targetId),
      () => admin.from("withdrawal_requests").update({ reviewed_by: null }).eq("reviewed_by", targetId),
      () => admin.from("deposit_requests").delete().eq("user_id", targetId),
      () => admin.from("withdrawal_requests").delete().eq("user_id", targetId),
      () => admin.from("user_notifications").delete().eq("user_id", targetId),
      () => admin.from("wallet_transactions").delete().eq("user_id", targetId),
    ];
    for (const step of cleanupSteps) {
      const { error } = await step();
      if (error) return reply({ error: "Account cleanup stopped before Auth deletion: " + error.message }, 500);
    }

    const { error: deleteAuthError } = await admin.auth.admin.deleteUser(targetId);
    if (deleteAuthError) return reply({ error: "Linked records were cleaned, but Auth account deletion failed: " + deleteAuthError.message }, 500);

    const { error: deleteProfileError } = await admin.from("profiles").delete().eq("id", targetId);
    if (deleteProfileError) return reply({ error: "Auth account deleted, but profile cleanup failed: " + deleteProfileError.message }, 500);

    return reply({ success: true, action: "delete" });
  } catch (error) {
    console.error("admin-users request failed:", error);
    return reply({ error: "The admin request failed unexpectedly. Check the Edge Function logs for details." }, 500);
  }
});