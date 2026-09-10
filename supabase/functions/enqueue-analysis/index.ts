import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };

Deno.serve(async (request) => {
  if (request.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
  try {
    const input = await request.json();
    const deviceId = request.headers.get("x-pinlogy-device") ?? "";
    if (!/^[0-9a-f-]{32,40}$/i.test(deviceId)) {
      return reply({ error: "device_id_required" }, 400);
    }
    const deviceHash = await sha256(deviceId);
    const action = String(input.action ?? "enqueue");
    if (action === "status") return status(input, deviceHash);
    if (action !== "enqueue") return reply({ error: "invalid_action" }, 400);

    const sourcePostId = String(input.source_post_id ?? "");
    if (!sourcePostId) return reply({ error: "invalid_request" }, 400);
    const payload = { ...input };
    delete payload.action;
    delete payload.notification_token;
    delete payload.notification_enabled;

    const db = adminClient();
    const { data, error } = await db.from("async_analysis_jobs").insert({
      source_post_id: sourcePostId,
      device_hash: deviceHash,
      device_id: deviceId,
      status: "pending",
      request_json: payload,
      notification_token: validFcmToken(input.notification_token),
      notification_enabled: input.notification_enabled === true,
    }).select("id").single();
    if (error || data == null) {
      console.error("async_job_insert_failed", error?.message);
      return reply({ error: "job_create_failed" }, 500);
    }

    const jobId = String(data.id);
    console.info(
      "async_job_enqueued",
      jobId,
      `notification=${input.notification_enabled === true}`,
      `token=${validFcmToken(input.notification_token) != null}`,
    );
    EdgeRuntime.waitUntil(processJob(jobId));
    return reply({ job_id: jobId, status: "pending" }, 202);
  } catch (error) {
    console.error("async_enqueue_failed", String(error));
    return reply({ error: "invalid_request" }, 400);
  }
});

async function status(input: Record<string, unknown>, deviceHash: string) {
  const jobId = String(input.job_id ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(jobId)) return reply({ error: "invalid_job" }, 400);
  const { data, error } = await adminClient()
    .from("async_analysis_jobs")
    .select("status,result_json,error_message,updated_at")
    .eq("id", jobId)
    .eq("device_hash", deviceHash)
    .maybeSingle();
  if (error) {
    console.error("async_job_status_failed", error.message);
    return reply({ error: "status_failed" }, 500);
  }
  if (data == null) return reply({ error: "job_not_found" }, 404);
  return reply({
    job_id: jobId,
    status: data.status,
    result: data.status === "completed" ? data.result_json : null,
    error: data.status === "failed" ? data.error_message : null,
    updated_at: data.updated_at,
  });
}

async function processJob(jobId: string) {
  const db = adminClient();
  const { data: job, error } = await db.from("async_analysis_jobs")
    .select("*").eq("id", jobId).single();
  if (error || job == null) return;

  await db.from("async_analysis_jobs").update({
    status: "processing",
    updated_at: new Date().toISOString(),
  }).eq("id", jobId);

  try {
    const baseUrl = requiredEnv("SUPABASE_URL").replace(/\/$/, "");
    const serviceKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    const response = await fetch(`${baseUrl}/functions/v1/analyze-post`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${serviceKey}`,
        "apikey": serviceKey,
        "Content-Type": "application/json",
        "X-Pinlogy-Device": String(job.device_id),
        "X-Pinlogy-Async-Job": jobId,
      },
      body: JSON.stringify(job.request_json),
      // Instagram snapshotの完了待ちと、その後の画像別AI解析を許容する。
      signal: AbortSignal.timeout(240_000),
    });
    const body = await response.json().catch(() => ({ error: "invalid_response" }));
    if (!response.ok) {
      throw new Error(String(body.error ?? `analyze_http_${response.status}`));
    }
    const media = body?.shared_media;
    const returnedImageCount = Array.isArray(media?.image_data_urls)
      ? media.image_data_urls.length
      : 0;
    const { error: completionError } = await db.from("async_analysis_jobs").update({
      status: "completed",
      result_json: body,
      error_message: null,
      completed_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      request_json: {},
      device_id: null,
      notification_token: null,
    }).eq("id", jobId);
    if (completionError) {
      throw new Error(`job_result_save_failed:${completionError.message}`);
    }
    console.info(
      "async_job_completed",
      jobId,
      `images=${returnedImageCount}`,
      `notification=${job.notification_enabled === true}`,
      `token=${validFcmToken(job.notification_token) != null}`,
    );
    if (job.notification_enabled && job.notification_token) {
      await sendCompletionNotification(String(job.notification_token), jobId);
    }
  } catch (error) {
    console.error("async_job_failed", jobId, String(error));
    await db.from("async_analysis_jobs").update({
      status: "failed",
      error_message: userSafeError(error),
      completed_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      request_json: {},
      device_id: null,
      notification_token: null,
    }).eq("id", jobId);
  }
}

async function sendCompletionNotification(token: string, jobId: string) {
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID")?.trim();
  const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL")?.trim();
  const privateKey = Deno.env.get("FIREBASE_PRIVATE_KEY")
    ?.replaceAll("\\n", "\n").trim();
  if (!projectId || !clientEmail || !privateKey) {
    console.info("fcm_skipped_not_configured");
    return;
  }
  try {
    const key = await importPKCS8(privateKey, "RS256");
    const now = Math.floor(Date.now() / 1000);
    const assertion = await new SignJWT({
      scope: "https://www.googleapis.com/auth/firebase.messaging",
    })
      .setProtectedHeader({ alg: "RS256", typ: "JWT" })
      .setIssuer(clientEmail)
      .setSubject(clientEmail)
      .setAudience("https://oauth2.googleapis.com/token")
      .setIssuedAt(now)
      .setExpirationTime(now + 3600)
      .sign(key);
    const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion,
      }),
    });
    const tokenJson = await tokenResponse.json();
    const accessToken = String(tokenJson.access_token ?? "");
    if (!tokenResponse.ok || !accessToken) throw new Error("oauth_failed");
    const response = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            notification: {
              title: "Pinlogy",
              body: "投稿の解析が完了しました",
            },
            data: { type: "analysis_completed", job_id: jobId },
            apns: { payload: { aps: { sound: "default" } } },
          },
        }),
      },
    );
    if (!response.ok) {
      console.warn("fcm_send_failed", response.status, (await response.text()).slice(0, 300));
    } else {
      console.info("fcm_send_succeeded", jobId);
    }
  } catch (error) {
    console.warn("fcm_send_failed", String(error));
  }
}

function adminClient() {
  return createClient(
    requiredEnv("SUPABASE_URL"),
    requiredEnv("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
}

function requiredEnv(name: string) {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new Error(`missing_${name.toLowerCase()}`);
  return value;
}

function validFcmToken(value: unknown) {
  if (typeof value !== "string") return null;
  const token = value.trim();
  return token.length >= 20 && token.length <= 4096 ? token : null;
}

function userSafeError(error: unknown) {
  const text = String(error);
  if (text.includes("Timeout")) return "解析がタイムアウトしました";
  return "解析を完了できませんでした";
}

async function sha256(value: string) {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

function reply(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}
