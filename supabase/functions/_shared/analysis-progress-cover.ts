// Save one already-extracted image; never download or analyze the video again.
export async function publishProgressCover(options: {
  request: Request;
  jobId: string;
  image: string | undefined;
  supabaseUrl: string | undefined;
  serviceKey: string | undefined;
  fetcher?: typeof fetch;
}) {
  const { request, jobId, image, supabaseUrl, serviceKey } = options;
  if (!supabaseUrl || !serviceKey ||
    request.headers.get("authorization") !== `Bearer ${serviceKey}` ||
    !/^[0-9a-f-]{36}$/i.test(jobId) || typeof image !== "string") return;
  const match = /^data:image\/(jpeg|png|webp);base64,([A-Za-z0-9+/=]+)$/.exec(image);
  if (!match || match[2].length > 2_800_000) return;
  const transport = options.fetcher ?? fetch;
  const base = supabaseUrl.replace(/\/$/, "");
  const headers = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` };
  const jobUrl = `${base}/rest/v1/async_analysis_jobs?id=eq.${jobId}&status=eq.processing`;
  try {
    const jobResponse = await transport(`${jobUrl}&select=device_hash`, {
      headers, signal: AbortSignal.timeout(3000),
    });
    if (!jobResponse.ok) return;
    const rows = await jobResponse.json();
    const owner = rows?.[0]?.device_hash;
    if (typeof owner !== "string" || !/^[a-f0-9]{64}$/i.test(owner)) return;
    const binary = atob(match[2]);
    if (binary.length === 0 || binary.length > 2 * 1024 * 1024) return;
    const extension = match[1] === "jpeg" ? "jpg" : match[1];
    const path = `${owner}/${jobId}/progress.${extension}`;
    const uploaded = await transport(`${base}/storage/v1/object/recipe-analysis-media/${path}`, {
      method: "POST",
      headers: { ...headers, "Content-Type": `image/${match[1]}`, "x-upsert": "true" },
      body: Uint8Array.from(binary, (character) => character.charCodeAt(0)),
      signal: AbortSignal.timeout(5000),
    });
    if (!uploaded.ok) return;
    const result = await transport(jobUrl, {
      method: "PATCH",
      headers: { ...headers, "Content-Type": "application/json", Prefer: "return=minimal" },
      body: JSON.stringify({
        result_json: { shared_media: { image_storage_paths: [path], thumbnail_index: 0 } },
        updated_at: new Date().toISOString(),
      }),
      signal: AbortSignal.timeout(3000),
    });
    if (!result.ok) console.warn("analysis_progress_cover_save_failed", result.status);
  } catch {
    // A preview failure must not fail or restart the actual recipe job.
    console.warn("analysis_progress_cover_unavailable");
  }
}
