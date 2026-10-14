import { identityValues } from "../_shared/billing-identity.ts";
import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
const headers = { "Content-Type": "application/json; charset=utf-8" };
const monthlyProduct = Deno.env.get("REVENUECAT_MONTHLY_PRODUCT_ID") ?? "tsukurepi_monthly_490";
const annualProduct = Deno.env.get("REVENUECAT_ANNUAL_PRODUCT_ID") ?? "tsukurepi_annual_4980";
const creditsProduct = Deno.env.get("REVENUECAT_CREDITS_PRODUCT_ID") ?? "tsukurepi_credits_20_400";

Deno.serve(async (request) => {
  if (request.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
  const secret = Deno.env.get("REVENUECAT_WEBHOOK_SECRET") ?? "";
  if (!secret || request.headers.get("authorization") !== `Bearer ${secret}`) return reply({ error: "unauthorized" }, 401);
  try {
    const payload = await request.json();
    const event = payload?.event ?? payload;
    const id = String(event?.id ?? "").trim();
    const type = String(event?.type ?? "").toUpperCase();
    const customer = String(event?.app_user_id ?? "").trim();
    const product = String(event?.product_id ?? "").trim();
    const eventAt = millisToIso(event?.event_timestamp_ms);
    if (!id || !type || !eventAt) return reply({ error: "invalid_event" }, 400);
    const db = adminClient();
    let from: string[] = [], to: string[] = [];
    if (type === "TRANSFER") {
      // TRANSFER intentionally has no app_user_id. Ignore unknown anonymous aliases.
      from = await knownCustomerHashes(db, event?.transferred_from);
      to = await liveCustomerHashes(db, event?.transferred_to);
      if (from.length === 0 || to.length === 0) throw new Error("transfer_identity_unresolved");
    } else if (!uuid(customer)) {
      return reply({ error: "invalid_customer" }, 400);
    }
    if (type !== "TRANSFER") await bindLiveCustomer(db, customer);
    const bonus = type === "NON_RENEWING_PURCHASE" && product === creditsProduct;
    const plan = product === monthlyProduct ? "monthly" : product === annualProduct ? "annual" : null;
    const original = String(event?.original_transaction_id ?? "").trim();
    const transaction = String(event?.transaction_id ?? "").trim();
    const contract = bonus ? transaction : original;
    const key = contract
      ? await sha256(`${event?.store ?? "unknown"}:${event?.environment ?? "unknown"}:${bonus ? "credits" : "subscription"}:${contract}`)
      : null;
    // Do not retain raw provider IDs, subscriber attributes or the full event payload.
    const minimalPayload = {
      id, type, environment: event?.environment ?? null,
      grace_expires_at: type === "BILLING_ISSUE"
        ? millisToIso(event?.grace_period_expiration_at_ms) : null,
    };
    const { error } = await db.rpc("apply_billing_webhook", {
      p_event_id: id, p_type: type,
      p_customer_hash: uuid(customer) ? await sha256(customer) : null,
      p_product: product || null, p_payload: minimalPayload, p_plan: plan,
      p_started_at: millisToIso(event?.purchased_at_ms),
      p_expires_at: millisToIso(event?.expiration_at_ms), p_event_at: eventAt,
      p_contract_hash: key, p_from_hashes: from, p_to_hashes: to, p_bonus: bonus,
    });
    if (error) throw error;
    return reply({ received: true });
  } catch (error) {
    console.error("revenuecat_webhook_failed", error instanceof Error ? error.message : String(error));
    return reply({ error: "webhook_failed" }, 500);
  }
});

function uuid(value: string) { return /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(value); }
async function knownCustomerHashes(db: ReturnType<typeof createClient>, values: unknown): Promise<string[]> {
  if (!Array.isArray(values)) return [];
  const hashes = await Promise.all(values.filter((v): v is string => typeof v === 'string' && uuid(v)).map(sha256));
  if (!hashes.length) return [];
  const { data, error } = await db.from('billing_customer_links').select('customer_hash').in('customer_hash', hashes);
  if (error) throw error;
  return [...new Set((data ?? []).map((r) => String(r.customer_hash)))];
}
async function liveCustomerHashes(db: ReturnType<typeof createClient>, values: unknown): Promise<string[]> {
  if (!Array.isArray(values)) return [];
  const result: string[] = [];
  for (const value of [...new Set(values)]) {
    if (typeof value !== 'string' || !uuid(value)) continue;
    const { data, error } = await db.auth.admin.getUserById(value);
    if (error || !data.user || data.user.is_anonymous) continue;
    await bindLiveCustomer(db, value, data.user);
    result.push(await sha256(value));
  }
  return result;
}
async function bindLiveCustomer(db: ReturnType<typeof createClient>, id: string, knownUser?: any) {
  const user = knownUser ?? (await db.auth.admin.getUserById(id)).data.user;
  if (!user || user.is_anonymous) return;
  const markers = identityValues(user);
  if (!markers.length) throw new Error('verified_identity_required');
  const secret = requiredEnv('TRIAL_IDENTITY_HMAC_SECRET');
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret),
    {name:'HMAC',hash:'SHA-256'},false,['sign']);
  const hashes = await Promise.all(markers.map(async (value) => {
    const digest = await crypto.subtle.sign('HMAC',key,new TextEncoder().encode(value));
    return [...new Uint8Array(digest)].map((b)=>b.toString(16).padStart(2,'0')).join('');
  }));
  const {error} = await db.rpc('bind_billing_identity',{
    p_user_id:id,p_user_hash:await sha256(id),p_identity_hashes:hashes,
  });
  if(error) throw error;
}
function adminClient() {
  return createClient(requiredEnv("SUPABASE_URL"), requiredEnv("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { persistSession: false, autoRefreshToken: false },
  });
}
function millisToIso(value: unknown) {
  const ms = Number(value);
  return Number.isFinite(ms) && ms > 0 ? new Date(ms).toISOString() : null;
}
async function sha256(value: string) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2,"0")).join("");
}
function requiredEnv(name: string) {
  const value = Deno.env.get(name); if (!value) throw new Error(`${name}_missing`); return value;
}
function reply(value: unknown,status=200) { return new Response(JSON.stringify(value),{status,headers}); }
