import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";

const headers = { "Content-Type": "application/json; charset=utf-8" };
const monthlyProduct = Deno.env.get("REVENUECAT_MONTHLY_PRODUCT_ID") ?? "tsukurepi_monthly_490";
const annualProduct = Deno.env.get("REVENUECAT_ANNUAL_PRODUCT_ID") ?? "tsukurepi_annual_4980";
const creditsProduct = Deno.env.get("REVENUECAT_CREDITS_PRODUCT_ID") ?? "tsukurepi_credits_20_400";

Deno.serve(async (request) => {
  if (request.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
  const expected = Deno.env.get("REVENUECAT_WEBHOOK_SECRET") ?? "";
  if (!expected || request.headers.get("authorization") !== `Bearer ${expected}`) {
    return reply({ error: "unauthorized" }, 401);
  }
  let savedEventId = "";
  try {
    const payload = await request.json();
    const event = payload?.event ?? payload;
    const eventId = String(event?.id ?? "").trim();
    savedEventId = eventId;
    const eventType = String(event?.type ?? "").toUpperCase();
    const appUserId = String(event?.app_user_id ?? "").trim();
    const productId = String(event?.product_id ?? "").trim();
    if (!eventId || !eventType || !/^[0-9a-f-]{32,40}$/i.test(appUserId)) {
      return reply({ error: "invalid_event" }, 400);
    }
    const db = adminClient();
    const { error: ledgerError } = await db.from("revenuecat_webhook_events").insert({
      event_id: eventId, event_type: eventType, app_user_id: appUserId,
      product_id: productId || null, payload,
    });
    if (ledgerError?.code === "23505") return reply({ received: true, duplicate: true });
    if (ledgerError) throw ledgerError;

    const deviceHash = await sha256(appUserId);
    if (eventType === "NON_RENEWING_PURCHASE" && productId === creditsProduct) {
      const { error } = await db.rpc("add_billing_bonus", {
        p_device_hash: deviceHash, p_amount: 20,
      });
      if (error) throw error;
      return reply({ received: true });
    }

    const plan = productId === annualProduct
      ? "annual"
      : productId === monthlyProduct
      ? "monthly"
      : null;
    const expiresAt = millisToIso(event?.expiration_at_ms);
    const purchasedAt = millisToIso(event?.purchased_at_ms) ?? new Date().toISOString();
    if (plan && ["INITIAL_PURCHASE", "RENEWAL", "UNCANCELLATION", "PRODUCT_CHANGE"].includes(eventType)) {
      const { error } = await db.rpc("activate_billing_plan", {
        p_device_hash: deviceHash, p_plan: plan,
        p_started_at: purchasedAt, p_expires_at: expiresAt,
      });
      if (error) throw error;
    } else if (["EXPIRATION", "BILLING_ISSUE"].includes(eventType) && expiresAt && Date.parse(expiresAt) <= Date.now()) {
      const { error } = await db.rpc("expire_billing_plan", { p_device_hash: deviceHash });
      if (error) throw error;
    }
    return reply({ received: true });
  } catch (error) {
    console.error("revenuecat_webhook_failed", String(error));
    if (savedEventId) {
      await adminClient().from("revenuecat_webhook_events").delete()
        .eq("event_id", savedEventId);
    }
    return reply({ error: "webhook_failed" }, 500);
  }
});

function adminClient() {
  return createClient(requiredEnv("SUPABASE_URL"), requiredEnv("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}

function millisToIso(value: unknown) {
  const milliseconds = Number(value);
  return Number.isFinite(milliseconds) && milliseconds > 0
    ? new Date(milliseconds).toISOString()
    : null;
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
