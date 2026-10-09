import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const headers = { "Content-Type": "application/json; charset=utf-8" };

Deno.serve(async (request) => {
  if (request.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
  const deviceId = request.headers.get("x-pinlogy-device") ?? "";
  if (!/^[0-9a-f-]{32,40}$/i.test(deviceId)) return reply({ error: "device_id_required" }, 400);
  let stage = "initialize";
  try {
    const deviceHash = await sha256(deviceId);
    const db = createClient(requiredEnv("SUPABASE_URL"), requiredEnv("SUPABASE_SERVICE_ROLE_KEY"), {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    stage = "authenticate";
    const userId = await authenticatedUserId(request);
    if (userId == null) return reply({ error: "authentication_required" }, 401);
    const userHash = await sha256(userId);
    stage = "link_account";
    const linked = await db.rpc("link_billing_account", {
      p_device_hash: deviceHash,
      p_user_id: userId,
      p_user_hash: userHash,
    });
    if (linked.error) throw linked.error;
    const accountHash = String(linked.data ?? userHash);
    stage = "load_trial_identity";
    const identities = await trialIdentityHashes(db, userId);
    stage = "claim_trial";
    const trial = await db.rpc("enforce_billing_trial_claim", {
      p_account_hash: accountHash,
      p_user_id: userId,
      p_identity_hashes: identities,
    });
    if (trial.error) throw trial.error;
    stage = "read_status";
    const { data, error } = await db.rpc("billing_status", { p_device_hash: accountHash });
    if (error) throw error;
    return reply({ ...data, app_user_id: userId, account_linked: true });
  } catch (error) {
    console.error(
      "billing_status_failed",
      JSON.stringify({ stage, error: serializeError(error) }),
    );
    return reply({ error: "billing_status_failed", stage }, 500);
  }
});

function serializeError(error: unknown) {
  if (error instanceof Error) {
    return { name: error.name, message: error.message, stack: error.stack };
  }
  if (typeof error === "object" && error !== null) {
    const value = error as Record<string, unknown>;
    return {
      code: value.code,
      message: value.message,
      details: value.details,
      hint: value.hint,
    };
  }
  return { message: String(error) };
}

async function authenticatedUserId(request: Request) {
  const authorization = request.headers.get("authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "").trim();
  if (!token) return null;
  const auth = createClient(requiredEnv("SUPABASE_URL"), requiredEnv("SUPABASE_ANON_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const { data, error } = await auth.auth.getUser(token);
  if (error || data.user == null || data.user.is_anonymous === true) return null;
  return data.user.id;
}

async function trialIdentityHashes(db: ReturnType<typeof createClient>, userId: string) {
  const { data, error } = await db.auth.admin.getUserById(userId);
  if (error || data.user == null) throw error ?? new Error("user_not_found");
  const values = (data.user.identities ?? []).flatMap((identity) => {
    const provider = String(identity.provider ?? "").toLowerCase();
    const id = String(identity.identity_id ?? identity.id ?? "").trim();
    return ["apple", "google"].includes(provider) && id
      ? [`${provider}:${id}`]
      : [];
  });

  const confirmedEmail = data.user.email_confirmed_at
    ? String(data.user.email ?? "").trim().toLowerCase()
    : "";
  if (confirmedEmail) {
    values.push(`email:${confirmedEmail}`);
  }

  if (values.length === 0) throw new Error("verified_identity_required");
  return Promise.all([...new Set(values)].map(hmacIdentity));
}

async function hmacIdentity(value: string) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(requiredEnv("TRIAL_IDENTITY_HMAC_SECRET")),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const digest = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function sha256(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name}_missing`);
  return value;
}

function reply(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), { status, headers });
}
