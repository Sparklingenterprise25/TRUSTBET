import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const encoder = new TextEncoder();

function b64(value: string) {
  return Uint8Array.from(atob(value), (c) => c.charCodeAt(0));
}
async function digest(value: string, pepper: string) {
  const result = await crypto.subtle.digest("SHA-256", encoder.encode(pepper + ":" + value));
  return Array.from(new Uint8Array(result), (x) => x.toString(16).padStart(2, "0")).join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return reply({ error: "Method not allowed." }, 405);

  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const pepper = Deno.env.get("TRUSTBET_RECOVERY_HASH_PEPPER");
  if (!url || !serviceKey || !pepper) return reply({ error: "Recovery service is not configured." }, 503);

  let body: { identifier?: string; code?: string; newPassword?: string };
  try { body = await req.json(); } catch { return reply({ error: "Invalid request." }, 400); }

  const identifier = String(body.identifier || "").trim();
  const code = String(body.code || "").trim();
  const newPassword = String(body.newPassword || "");
  if (!identifier || !/^\d{6}$/.test(code) || newPassword.length < 8 || newPassword.length > 72) {
    return reply({ error: "Enter your account phone/email, six-digit recovery code, and a password of at least 8 characters." }, 400);
  }

  const admin = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const normalized = identifier.toLowerCase();
  const identifierHash = await digest("recovery-identifier:" + normalized, pepper);
  const { data: allowed, error: rateError } = await admin.rpc("trustbet_allow_recovery_attempt", {
    p_identifier_hash: identifierHash,
  });
  if (rateError) return reply({ error: "Recovery service is temporarily unavailable." }, 503);
  if (allowed !== true) return reply({ error: "Too many recovery attempts. Please wait 15 minutes before trying again." }, 429);
  const query = normalized.includes("@")
    ? admin.from("profiles").select("id").ilike("email", normalized).maybeSingle()
    : admin.from("profiles").select("id").eq("phone", identifier).maybeSingle();
  const { data: profile, error: lookupError } = await query;
  // Keep unknown accounts and invalid/used codes indistinguishable to callers.
  if (lookupError || !profile?.id) return reply({ error: "The recovery details could not be verified." }, 400);

  const codeHash = await digest(code, pepper);
  const claimToken = crypto.randomUUID();
  const { data: claimed, error: claimError } = await admin.rpc("trustbet_claim_recovery_code", {
    p_user_id: profile.id,
    p_code_hash: codeHash,
    p_claim_token: claimToken,
  });
  if (claimError || claimed !== true) return reply({ error: "The recovery details could not be verified." }, 400);

  const { error: passwordError } = await admin.auth.admin.updateUserById(profile.id, { password: newPassword });
  if (passwordError) {
    await admin.rpc("trustbet_release_recovery_code", { p_user_id: profile.id, p_claim_token: claimToken });
    return reply({ error: "Password reset could not be completed. Please try again." }, 500);
  }

  const { data: finished, error: finishError } = await admin.rpc("trustbet_finish_recovery_code", {
    p_user_id: profile.id,
    p_claim_token: claimToken,
  });
  if (finishError || finished !== true) {
    // Password has changed, but the code could not be marked used. Fail closed and alert operators.
    console.error("Password changed but recovery code finalization failed for user", profile.id);
    return reply({ error: "Your password was changed, but recovery finalization needs administrator attention. Contact support before retrying." }, 500);
  }

  return reply({ success: true, message: "Password reset successfully. You can now sign in with your new password." });
});
