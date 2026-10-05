import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT, decodeJwt } from "npm:jose@5.9.6";

const headers = { "Content-Type": "application/json; charset=utf-8" };

Deno.serve(async (request) => {
  if (request.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
  try {
    const db = createClient(requiredEnv("SUPABASE_URL"), requiredEnv("SUPABASE_SERVICE_ROLE_KEY"), {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const token = (request.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "").trim();
    if (!token) return reply({ error: "authentication_required" }, 401);
    const authenticated = await db.auth.getUser(token);
    const user = authenticated.data.user;
    if (authenticated.error || user == null || user.is_anonymous === true) {
      return reply({ error: "authentication_required" }, 401);
    }
    const adminUser = await db.auth.admin.getUserById(user.id);
    if (adminUser.error || adminUser.data.user == null) throw adminUser.error;
    const identities = adminUser.data.user.identities ?? [];
    const identityValues = identities.flatMap((identity) => {
      const provider = String(identity.provider ?? "").toLowerCase();
      const id = String(identity.identity_id ?? identity.id ?? "").trim();
      return ["apple", "google"].includes(provider) && id ? [`${provider}:${id}`] : [];
    });
    if (identityValues.length === 0) return reply({ error: "verified_identity_required" }, 409);

    const appleIdentity = identities.find((identity) => identity.provider === "apple");
    if (appleIdentity != null) {
      const input = await request.json().catch(() => ({}));
      const authorizationCode = String(input.apple_authorization_code ?? "").trim();
      if (!authorizationCode) return reply({ error: "apple_reauthentication_required" }, 409);
      const appleSubject = String(appleIdentity.identity_id ?? appleIdentity.id ?? "");
      await revokeAppleAuthorization(authorizationCode, appleSubject);
    }

    const identityHashes = await Promise.all(identityValues.map(hmacIdentity));
    const prepared = await db.rpc("prepare_account_deletion", {
      p_user_id: user.id,
      p_identity_hashes: identityHashes,
    });
    if (prepared.error) throw prepared.error;
    const accountHashes = Array.isArray(prepared.data) ? prepared.data.map(String) : [];
    await removeAnalysisMedia(db, accountHashes);
    const deleted = await db.auth.admin.deleteUser(user.id);
    if (deleted.error) throw deleted.error;
    return reply({ deleted: true });
  } catch (error) {
    console.error("account_deletion_failed", String(error));
    return reply({ error: "account_deletion_failed" }, 500);
  }
});

async function revokeAppleAuthorization(code: string, expectedSubject: string) {
  const clientId = requiredEnv("APPLE_CLIENT_ID");
  const clientSecret = await appleClientSecret(clientId);
  const tokenResponse = await fetch("https://appleid.apple.com/auth/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      code,
      grant_type: "authorization_code",
    }),
  });
  const tokens = await tokenResponse.json();
  if (!tokenResponse.ok) throw new Error(`apple_token_exchange_failed:${tokenResponse.status}`);
  const subject = tokens.id_token ? String(decodeJwt(String(tokens.id_token)).sub ?? "") : "";
  if (!subject || subject !== expectedSubject) throw new Error("apple_identity_mismatch");
  const revocationToken = String(tokens.refresh_token ?? tokens.access_token ?? "");
  if (!revocationToken) throw new Error("apple_revocation_token_missing");
  const revoked = await fetch("https://appleid.apple.com/auth/revoke", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      client_id: clientId,
      client_secret: clientSecret,
      token: revocationToken,
      token_type_hint: tokens.refresh_token ? "refresh_token" : "access_token",
    }),
  });
  if (!revoked.ok) throw new Error(`apple_revocation_failed:${revoked.status}`);
}

async function appleClientSecret(clientId: string) {
  const privateKey = requiredEnv("APPLE_PRIVATE_KEY").replace(/\\n/g, "\n");
  const key = await importPKCS8(privateKey, "ES256");
  return await new SignJWT({})
    .setProtectedHeader({ alg: "ES256", kid: requiredEnv("APPLE_KEY_ID") })
    .setIssuer(requiredEnv("APPLE_TEAM_ID"))
    .setSubject(clientId)
    .setAudience("https://appleid.apple.com")
    .setIssuedAt()
    .setExpirationTime("5m")
    .sign(key);
}

async function removeAnalysisMedia(db: ReturnType<typeof createClient>, accountHashes: string[]) {
  for (const accountHash of accountHashes) {
    const paths: string[] = [];
    const jobs = await db.storage.from("recipe-analysis-media").list(accountHash, { limit: 1000 });
    if (jobs.error) continue;
    for (const job of jobs.data ?? []) {
      const files = await db.storage.from("recipe-analysis-media").list(`${accountHash}/${job.name}`, { limit: 1000 });
      for (const file of files.data ?? []) paths.push(`${accountHash}/${job.name}/${file.name}`);
    }
    if (paths.length > 0) await db.storage.from("recipe-analysis-media").remove(paths);
  }
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

function requiredEnv(name: string) {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`${name}_missing`);
  return value;
}

function reply(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), { status, headers });
}
