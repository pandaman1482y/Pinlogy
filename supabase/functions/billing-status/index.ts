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
    const { data, error } = await db.rpc("billing_status", { p_device_hash: deviceHash });
    if (error) throw error;
    return reply({ ...data, app_user_id: deviceId });
  } catch (error) {
    console.error("billing_status_failed", String(error));
    return reply({ error: "billing_status_failed" }, 500);
  }
});

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
