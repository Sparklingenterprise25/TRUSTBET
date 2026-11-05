import { createClient } from "npm:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const reply = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });
const encoder = new TextEncoder();

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
  const isPhoneIdentifier = !identifier.includes("@");
  const validPassword = isPhoneIdentifier
    ? /^(?=.{8,15}$)(?=[0-9]*[A-Za-z][0-9]*$)[A-Za-z0-9]+$/.test(newPassword)
    : newPassword.length >= 8 && newPassword.length <= 15;
  if (!identifier || !/^\d{6}$/.test(code) || !validPassword) {
    return reply({
      error: isPhoneIdentifier
        ? "Phone passwords must be 8–15 characters: exactly one letter and all remaining characters numbers."
        : "Email account passwords must be 8–15 characters.",
    }, 400);
  }

  const admin = createClient(url, serviceKey, { auth: { autoRefreshToken: false, persistSession: false } });
  const normalized = isPhoneIdentifier ? identifier : identifier.toLowerCase();
  const identifierHash = await digest("recovery-identifier:" + normalized, pepper);
  const { data: allowed, error: rateError } = await admin.rpc("trustbet_allow_recovery_attempt", {
    p_identifier_hash: identifierHash,
  });
  if (rateError) {
    console.error("recovery_reset_rate_limit_error", { code: rateError.code || null });
    return reply({ error: "Recovery service is temporarily unavailable." }, 503);
  }
  if (allowed !== true) return reply({ error: "Too many recovery attempts. Please wait 15 minutes before trying again." }, 429);

  let profileQuery;
  if (isPhoneIdentifier) {
    const digits = identifier.replace(/\D/g, "");
    const candidates = Array.from(new Set([identifier, digits, digits ? "+" + digits : ""].filter(Boolean)));
    profileQuery = admin.from("profiles").select("id").in("phone", candidates).maybeSingle();
  } else {
    profileQuery = admin.from("profiles").select("id").ilike("email", normalized).maybeSingle();
  }
  const { data: profile, error: lookupError } = await profileQuery;
  if (lookupError || !profile?.id) {
    console.warn("recovery_reset_rejected", { stage: "profile_lookup", code: lookupError?.code || null });
    return reply({ error: "The recovery details could not be verified. Check the full registered phone number and recovery code." }, 400);
  }

  const codeHash = await digest(code, pepper);
  const claimToken = crypto.randomUUID();
  const { data: claimed, error: claimError } = await admin.rpc("trustbet_claim_recovery_code", {
    p_user_id: profile.id,
    p_code_hash: codeHash,
    p_claim_token: claimToken,
  });
  if (claimError || claimed !== true) {
    console.warn("recovery_reset_rejected", { stage: "recovery_code_claim", code: claimError?.code || null });
    return reply({ error: "The recovery details could not be verified. Check that the six-digit code is unused and belongs to this account." }, 400);
  }

  const { error: passwordError } = await admin.auth.admin.updateUserById(profile.id, { password: newPassword });
  if (passwordError) {
    await admin.rpc("trustbet_release_recovery_code", { p_user_id: profile.id, p_claim_token: claimToken });
    console.error("recovery_reset_password_update_failed", { status: passwordError.status || null, code: passwordError.code || null });
    return reply({ error: "Password reset could not be completed. Please try again." }, 500);
  }

  const { data: finished, error: finishError } = await admin.rpc("trustbet_finish_recovery_code", {
    p_user_id: profile.id,
    p_claim_token: claimToken,
  });
  if (finishError || finished !== true) {
    console.error("recovery_reset_finalization_failed", { code: finishError?.code || null });
    return reply({ error: "Your password was changed, but recovery finalization needs administrator attention. Contact support before retrying." }, 500);
  }

  return reply({ success: true, message: "Password reset successfully. You can now sign in with your new password." });
});
