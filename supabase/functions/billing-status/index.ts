import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const headers = { "Content-Type": "application/json; charset=utf-8" };

Deno.serve(async (request) => {
  if (request.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
  const deviceId = request.headers.get("x-pinlogy-device") ?? "";
  if (!/^[0-9a-f-]{32,40}$/i.test(deviceId)) return reply({ error: "device_id_required" }, 400);
  try {
    const deviceHash = await sha256(deviceId);
    const db = createClient(requiredEnv("SUPABASE_URL"), requiredEnv("SUPABASE_SERVICE_ROLE_KEY"), {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const userId = await authenticatedUserId(request);
    let accountHash = deviceHash;
    if (userId != null) {
      const userHash = await sha256(userId);
      const linked = await db.rpc("link_billing_account", {
        p_device_hash: deviceHash,
        p_user_id: userId,
        p_user_hash: userHash,
      });
      if (linked.error) throw linked.error;
      accountHash = String(linked.data ?? userHash);
    } else {
      const resolved = await db.rpc("resolve_billing_account_hash", {
        p_device_hash: deviceHash,
      });
      if (resolved.error) throw resolved.error;
      accountHash = String(resolved.data ?? deviceHash);
    }
    const { data, error } = await db.rpc("billing_status", { p_device_hash: accountHash });
    if (error) throw error;
    return reply({ ...data, app_user_id: userId ?? deviceId, account_linked: userId != null });
  } catch (error) {
    console.error("billing_status_failed", String(error));
    return reply({ error: "billing_status_failed" }, 500);
  }
});

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
