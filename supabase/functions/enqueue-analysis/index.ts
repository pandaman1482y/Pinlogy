import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
import { importPKCS8, SignJWT } from "npm:jose@5.9.6";

const jsonHeaders = { "Content-Type": "application/json; charset=utf-8" };

Deno.serve(async (request) => {
  if (request.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
  try {
    const input = await request.json();
    const action = String(input.action ?? "enqueue");
    // Run the expensive task in an independent HTTP invocation. The Share
    // Extension and enqueue request may end immediately after this handoff.
    if (action === "process") {
      if (!isServiceRequest(request)) {
        return reply({ error: "worker_unauthorized" }, 401);
      }
      const jobId = String(input.job_id ?? "");
      if (!/^[0-9a-f-]{36}$/i.test(jobId)) {
        return reply({ error: "invalid_job" }, 400);
      }
      // Acknowledge immediately. The expensive phase runs independently,
      // so dispatchers never form a chain of waiting HTTP calls.
      EdgeRuntime.waitUntil(processJob(jobId));
      return reply({ job_id: jobId, status: "processing" }, 202);
    }
    const deviceId = request.headers.get("x-pinlogy-device") ?? "";
    if (!/^[0-9a-f-]{32,40}$/i.test(deviceId)) {
      return reply({ error: "device_id_required" }, 400);
    }
    const deviceHash = await sha256(deviceId);
    if (action === "status") return status(input, deviceHash);
    if (action === "cancel") return cancel(input, deviceHash);
    if (action === "test_notification") {
      const token = validFcmToken(input.notification_token);
      if (token == null) return reply({ error: "notification_token_required" }, 400);
      const sent = await sendCompletionNotification(token, "test", null);
      return sent
        ? reply({ sent: true })
        : reply({ error: "notification_send_failed" }, 502);
    }
    if (action !== "enqueue") return reply({ error: "invalid_action" }, 400);

    const sourcePostId = String(input.source_post_id ?? "");
    if (!sourcePostId) return reply({ error: "invalid_request" }, 400);
    const payload = { ...input };
    delete payload.action;
    delete payload.notification_token;
    delete payload.notification_enabled;
    delete payload.__bright_data_tiktok;
    delete payload.tiktok_external_post;

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
    EdgeRuntime.waitUntil(dispatchJob(jobId));
    return reply({ job_id: jobId, status: "pending" }, 202);
  } catch (error) {
    console.error("async_enqueue_failed", String(error));
    return reply({ error: "invalid_request" }, 400);
  }
});

async function dispatchJob(jobId: string) {
  try {
    const baseUrl = requiredEnv("SUPABASE_URL").replace(/\/$/, "");
    const serviceKey = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
    console.info("async_worker_dispatch_started", jobId);
    const response = await fetch(`${baseUrl}/functions/v1/enqueue-analysis`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${serviceKey}`,
        "apikey": serviceKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ action: "process", job_id: jobId }),
      signal: AbortSignal.timeout(600_000),
    });
    if (!response.ok) {
      console.error(
        "async_worker_dispatch_failed",
        jobId,
        response.status,
        (await response.text()).slice(0, 300),
      );
      await markDispatchFailed(jobId);
    } else {
      console.info("async_worker_dispatch_completed", jobId);
    }
  } catch (error) {
    console.error("async_worker_dispatch_failed", jobId, String(error));
    await markDispatchFailed(jobId);
  }
}

async function markDispatchFailed(jobId: string) {
  await adminClient().from("async_analysis_jobs").update({
    status: "failed",
    error_message: "バックグラウンド解析を開始できませんでした",
    completed_at: new Date().toISOString(),
    updated_at: new Date().toISOString(),
  }).eq("id", jobId).eq("status", "pending");
}

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
  let result = null;
  if (data.status === "completed") {
    try {
      result = await hydrateResultImages(data.result_json);
    } catch (error) {
      console.error("async_job_media_sign_failed", jobId, String(error));
      return reply({ error: "result_media_unavailable" }, 503);
    }
  }
  return reply({
    job_id: jobId,
    status: data.status,
    result,
    error: data.status === "failed" ? data.error_message : null,
    updated_at: data.updated_at,
  });
}

async function cancel(input: Record<string, unknown>, deviceHash: string) {
  const jobId = String(input.job_id ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(jobId)) return reply({ error: "invalid_job" }, 400);
  const now = new Date().toISOString();
  const { data, error } = await adminClient().from("async_analysis_jobs")
    .update({
      status: "cancelled",
      error_message: null,
      completed_at: now,
      updated_at: now,
      request_json: {},
      device_id: null,
      notification_token: null,
    })
    .eq("id", jobId)
    .eq("device_hash", deviceHash)
    .in("status", ["pending", "processing"])
    .select("id")
    .maybeSingle();
  if (error) {
    console.error("async_job_cancel_failed", jobId, error.message);
    return reply({ error: "cancel_failed" }, 500);
  }
  return data == null
    ? reply({ error: "job_not_found" }, 404)
    : reply({ job_id: jobId, status: "cancelled" });
}

async function processJob(jobId: string) {
  const db = adminClient();
  const { data: job, error } = await db.from("async_analysis_jobs")
    .select("*").eq("id", jobId).single();
  if (error || job == null) return;

  if (job.status !== "pending") {
    console.info("async_worker_skipped", jobId, `status=${job.status}`);
    return;
  }
  const { data: claimed, error: claimError } = await db
    .from("async_analysis_jobs")
    .update({ status: "processing", updated_at: new Date().toISOString() })
    .eq("id", jobId)
    .eq("status", "pending")
    .select("id")
    .maybeSingle();
  if (claimError || claimed == null) {
    console.info("async_worker_claim_skipped", jobId);
    return;
  }

  try {
    const preparedPayload = await prepareTikTokPayload(jobId, job.request_json);
    if (preparedPayload == null) return;
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
      body: JSON.stringify(preparedPayload),
      // Instagram snapshotの完了待ちと、その後の画像別AI解析を許容する。
      signal: AbortSignal.timeout(540_000),
    });
    const body = await response.json().catch(() => ({ error: "invalid_response" }));
    if (!response.ok) {
      throw new Error(String(body.error ?? `analyze_http_${response.status}`));
    }
    const media = body?.shared_media;
    const returnedImageCount = Array.isArray(media?.image_data_urls)
      ? media.image_data_urls.length
      : 0;
    const storedBody = await persistResultImages(jobId, String(job.device_hash), body);
    const { data: completed, error: completionError } = await db
      .from("async_analysis_jobs").update({
      status: "completed",
      result_json: storedBody,
      error_message: null,
      completed_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
      request_json: {},
      device_id: null,
      notification_token: null,
    }).eq("id", jobId).eq("status", "processing").select("id").maybeSingle();
    if (completionError) {
      throw new Error(`job_result_save_failed:${completionError.message}`);
    }
    if (completed == null) {
      console.info("async_job_completion_skipped", jobId, "cancelled_or_replaced");
      return;
    }
    console.info(
      "async_job_completed",
      jobId,
      `images=${returnedImageCount}`,
      `notification=${job.notification_enabled === true}`,
      `token=${validFcmToken(job.notification_token) != null}`,
    );
    if (job.notification_enabled && job.notification_token) {
      await sendCompletionNotification(
        String(job.notification_token),
        jobId,
        String(job.source_post_id),
      );
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
    }).eq("id", jobId).eq("status", "processing");
  }
}

type TikTokSnapshotState = {
  snapshot_id: string;
  attempt: number;
  started_at: string;
};

type TikTokExternalPost = {
  description: string;
  title: string;
};

// Bright Dataの開始・進捗確認を別々のEdge Function実行へ分割する。
// 1回の実行ではAPIを1回だけ呼び、未完了ならDBへ状態を戻して終了する。
async function prepareTikTokPayload(
  jobId: string,
  requestValue: unknown,
): Promise<Record<string, unknown> | null> {
  const request = requestValue != null && typeof requestValue === "object"
    ? { ...(requestValue as Record<string, unknown>) }
    : {};
  const rawUrl = String(request.url ?? "").trim();
  if (!isTikTokVideoUrl(rawUrl)) return request;

  const token = requiredEnv("BRIGHT_DATA_API_TOKEN");
  const state = readTikTokSnapshotState(request.__bright_data_tiktok);
  if (state == null) {
    const snapshotId = await triggerTikTokSnapshot(rawUrl, token);
    const nextState: TikTokSnapshotState = {
      snapshot_id: snapshotId,
      attempt: 0,
      started_at: new Date().toISOString(),
    };
    request.__bright_data_tiktok = nextState;
    console.info("async_tiktok_snapshot_started", jobId, snapshotId);
    await requeueTikTokSnapshot(jobId, request, 5_000);
    return null;
  }

  const elapsed = Date.now() - Date.parse(state.started_at);
  if (state.attempt >= 60 || !Number.isFinite(elapsed) || elapsed > 10 * 60_000) {
    throw new Error("bright_data_tiktok_snapshot_timeout");
  }

  const progress = await fetch(
    `https://api.brightdata.com/datasets/v3/progress/${encodeURIComponent(state.snapshot_id)}`,
    {
      headers: { "Authorization": `Bearer ${token}` },
      signal: AbortSignal.timeout(12_000),
    },
  );
  if (!progress.ok) {
    console.warn("async_tiktok_progress_failed", jobId, progress.status);
    request.__bright_data_tiktok = { ...state, attempt: state.attempt + 1 };
    await requeueTikTokSnapshot(jobId, request, 10_000);
    return null;
  }

  const progressJson = await progress.json();
  const status = String(progressJson?.status ?? "").toLowerCase();
  if (status === "failed") {
    throw new Error(
      `bright_data_tiktok_snapshot_failed:${String(progressJson?.error_message ?? "unknown").slice(0, 300)}`,
    );
  }
  if (status !== "ready") {
    request.__bright_data_tiktok = { ...state, attempt: state.attempt + 1 };
    console.info(
      "async_tiktok_snapshot_waiting",
      jobId,
      `attempt=${state.attempt + 1}`,
      `status=${status || "unknown"}`,
    );
    await requeueTikTokSnapshot(jobId, request, 10_000);
    return null;
  }

  const snapshot = await fetch(
    `https://api.brightdata.com/datasets/v3/snapshot/${encodeURIComponent(state.snapshot_id)}?format=json`,
    {
      headers: { "Authorization": `Bearer ${token}` },
      signal: AbortSignal.timeout(20_000),
    },
  );
  if (!snapshot.ok) {
    throw new Error(`bright_data_tiktok_snapshot_http_${snapshot.status}`);
  }
  const external = parseTikTokSnapshot(await snapshot.json());
  if (external == null) throw new Error("bright_data_tiktok_snapshot_invalid");

  delete request.__bright_data_tiktok;
  request.tiktok_external_post = external;
  console.info(
    "async_tiktok_snapshot_ready",
    jobId,
    `caption=${external.description.length}`,
  );
  return request;
}

async function triggerTikTokSnapshot(rawUrl: string, token: string) {
  const endpoint = new URL("https://api.brightdata.com/datasets/v3/trigger");
  endpoint.searchParams.set("dataset_id", "gd_lu702nij2f790tmv9h");
  endpoint.searchParams.set("include_errors", "true");
  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify([{ url: rawUrl }]),
    signal: AbortSignal.timeout(15_000),
  });
  if (!response.ok) {
    throw new Error(`bright_data_tiktok_trigger_http_${response.status}`);
  }
  const decoded = await response.json();
  const snapshotId = String(decoded?.snapshot_id ?? "").trim();
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(snapshotId)) {
    throw new Error("bright_data_tiktok_snapshot_missing");
  }
  return snapshotId;
}

async function requeueTikTokSnapshot(
  jobId: string,
  requestJson: Record<string, unknown>,
  delayMs: number,
) {
  const { data, error } = await adminClient().from("async_analysis_jobs")
    .update({
      status: "pending",
      request_json: requestJson,
      updated_at: new Date().toISOString(),
    })
    .eq("id", jobId)
    .eq("status", "processing")
    .select("id")
    .maybeSingle();
  if (error) throw new Error(`async_tiktok_requeue_failed:${error.message}`);
  if (data == null) return;
  EdgeRuntime.waitUntil(dispatchJobAfter(jobId, delayMs));
}

async function dispatchJobAfter(jobId: string, delayMs: number) {
  await new Promise((resolve) => setTimeout(resolve, delayMs));
  await dispatchJob(jobId);
}

function readTikTokSnapshotState(value: unknown): TikTokSnapshotState | null {
  if (value == null || typeof value !== "object") return null;
  const record = value as Record<string, unknown>;
  const snapshotId = String(record.snapshot_id ?? "").trim();
  const attempt = Number(record.attempt ?? 0);
  const startedAt = String(record.started_at ?? "");
  if (!/^[A-Za-z0-9_-]{8,128}$/.test(snapshotId)) return null;
  if (!Number.isInteger(attempt) || attempt < 0 || attempt > 60) return null;
  if (!Number.isFinite(Date.parse(startedAt))) return null;
  return { snapshot_id: snapshotId, attempt, started_at: startedAt };
}

function parseTikTokSnapshot(decoded: unknown): TikTokExternalPost | null {
  const rows = Array.isArray(decoded) ? decoded : [decoded];
  const row = rows.find((value) => value != null && typeof value === "object");
  if (row == null || typeof row !== "object") return null;
  const record = row as Record<string, unknown>;
  const description = String(
    record.description ?? record.caption ?? record.post_text ?? record.text ?? "",
  ).trim().slice(0, 12_000);
  const creator = String(
    record.profile_username ?? record.author_name ?? record.nickname ?? "",
  ).trim();
  return {
    description,
    title: creator ? `TikTok @${creator}` : "TikTok投稿",
  };
}

function isTikTokVideoUrl(rawUrl: string) {
  try {
    const url = new URL(rawUrl);
    const host = url.hostname.toLowerCase();
    return url.protocol === "https:" &&
      (host === "tiktok.com" || host.endsWith(".tiktok.com")) &&
      /\/@[^/]+\/video\/\d+\/?$/i.test(url.pathname);
  } catch {
    return false;
  }
}

const analysisMediaBucket = "recipe-analysis-media";

async function persistResultImages(
  jobId: string,
  deviceHash: string,
  body: Record<string, unknown>,
) {
  const media = body.shared_media;
  if (media == null || typeof media !== "object") return body;
  const mediaRecord = media as Record<string, unknown>;
  const values = Array.isArray(mediaRecord.image_data_urls)
    ? mediaRecord.image_data_urls
    : [];
  const paths: string[] = [];
  for (let index = 0; index < Math.min(values.length, 30); index++) {
    const decoded = decodeImageDataUrl(values[index]);
    if (decoded == null) continue;
    const path = `${deviceHash}/${jobId}/${index}.${decoded.extension}`;
    const { error } = await adminClient().storage.from(analysisMediaBucket)
      .upload(path, decoded.bytes, {
        contentType: decoded.contentType,
        upsert: true,
      });
    if (error) throw new Error(`job_media_save_failed:${error.message}`);
    paths.push(path);
  }
  if (paths.length !== values.length) {
    throw new Error(`job_media_save_failed:${paths.length}/${values.length}`);
  }
  return {
    ...body,
    shared_media: {
      ...mediaRecord,
      thumbnail_data_url: null,
      image_data_urls: [],
      image_storage_paths: paths,
    },
  };
}

async function hydrateResultImages(value: unknown) {
  if (value == null || typeof value !== "object") return value;
  const result = value as Record<string, unknown>;
  const media = result.shared_media;
  if (media == null || typeof media !== "object") return result;
  const mediaRecord = media as Record<string, unknown>;
  const paths = Array.isArray(mediaRecord.image_storage_paths)
    ? mediaRecord.image_storage_paths.filter((item): item is string => typeof item === "string")
    : [];
  if (paths.length === 0) return result;
  const urls: string[] = [];
  for (const path of paths) {
    const { data, error } = await adminClient().storage.from(analysisMediaBucket)
      .createSignedUrl(path, 60 * 60);
    if (!error && data?.signedUrl) urls.push(data.signedUrl);
  }
  if (urls.length !== paths.length) {
    throw new Error(`job_media_sign_failed:${urls.length}/${paths.length}`);
  }
  return {
    ...result,
    shared_media: {
      ...mediaRecord,
      thumbnail_data_url: urls[0] ?? null,
      image_data_urls: urls,
    },
  };
}

function decodeImageDataUrl(value: unknown) {
  if (typeof value !== "string") return null;
  const match = /^data:image\/(jpeg|png|webp);base64,([A-Za-z0-9+/=]+)$/.exec(value);
  if (match == null) return null;
  try {
    const binary = atob(match[2]);
    const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
    if (bytes.length === 0 || bytes.length > 2 * 1024 * 1024) return null;
    return {
      bytes,
      extension: match[1] === "jpeg" ? "jpg" : match[1],
      contentType: `image/${match[1]}`,
    };
  } catch {
    return null;
  }
}

function isServiceRequest(request: Request) {
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  return serviceKey != null && serviceKey.length > 0 &&
    request.headers.get("authorization") === `Bearer ${serviceKey}`;
}

async function sendCompletionNotification(
  token: string,
  jobId: string,
  sourcePostId: string | null,
) {
  const projectId = Deno.env.get("FIREBASE_PROJECT_ID")?.trim();
  const clientEmail = Deno.env.get("FIREBASE_CLIENT_EMAIL")?.trim();
  const privateKey = Deno.env.get("FIREBASE_PRIVATE_KEY")
    ?.replaceAll("\\n", "\n").trim();
  if (!projectId || !clientEmail || !privateKey) {
    console.info("fcm_skipped_not_configured");
    return false;
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
              title: "レシピの取り込みが完了しました",
              body: jobId === "test"
                ? "テスト通知を受信できました"
                : "材料と作り方を確認できます",
            },
            data: {
              type: "analysis_completed",
              job_id: jobId,
              source_post_id: sourcePostId ?? "",
            },
            apns: { payload: { aps: { sound: "default" } } },
          },
        }),
      },
    );
    if (!response.ok) {
      console.warn("fcm_send_failed", response.status, (await response.text()).slice(0, 300));
      return false;
    } else {
      console.info("fcm_send_succeeded", jobId);
      return true;
    }
  } catch (error) {
    console.warn("fcm_send_failed", String(error));
    return false;
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
