import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const headers = { "Content-Type": "application/json; charset=utf-8" };
const maxSocialImages = 10;
const maxVideoFrames = 20;
const maxAnalysisImages = maxSocialImages + maxVideoFrames;

Deno.serve(async (request) => {
  if (request.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
  let deviceId = "";
  let quotaReserved = false;
  try {
    const input = await request.json();
    const sourcePostId = String(input.source_post_id ?? "");
    if (!sourcePostId) return reply({ error: "invalid_request" }, 400);
    const sharedPage = await enrichSharedUrl(
      typeof input.url === "string" ? input.url : "",
    );
    if (input.preview_only === true) {
      const previewImages = await fetchSocialImages(
        (sharedPage?.image_urls ?? []).slice(0, maxSocialImages),
        sharedPage?.service ?? null,
      );
      return reply({
        source_post_id: sourcePostId,
        analysis_source: "preview_only",
        shared_media: sharedMedia(sharedPage, previewImages),
      });
    }

    const suppliedImages = validImages(input.image_data_urls)
      .slice(0, maxSocialImages);
    const selectedImagesOnly = input.selected_images_only === true;
    const suppliedImageIndexes = validImageIndexes(input.image_indexes);
    const instagramHasNoMedia = sharedPage?.service === "instagram" &&
      sharedPage.is_photo_post &&
      sharedPage.image_urls.length === 0 &&
      suppliedImages.length === 0;
    const availableText = [
      cleanSharedText(input.text, sharedPage),
      input.ocr_text,
      sharedPage?.title,
      sharedPage?.description,
    ].map((value) => String(value ?? "").trim())
      .filter((value) => {
        if (value.length < 3 || /^https?:\/\//i.test(value)) return false;
        const normalized = value.toLowerCase();
        return ![
          "instagram",
          "login • instagram",
          "ログイン • instagram",
        ].includes(normalized) &&
          !normalized.includes("create an account or log in to instagram");
      });
    if (instagramHasNoMedia && availableText.length === 0) {
      return reply({
        source_post_id: sourcePostId,
        candidates: [],
        recipes: [],
        raw_summary:
          "Instagramの投稿画像と投稿文を取得できませんでした。材料や工程が写ったスクリーンショットを追加してください。",
        analysis_source: "instagram_media_unavailable",
        shared_media: sharedMedia(sharedPage, []),
      });
    }

    const apiKey = Deno.env.get("OPENAI_API_KEY");
    if (!apiKey) return reply({ error: "ai_not_configured" }, 503);
    deviceId = request.headers.get("x-pinlogy-device") ?? "";
    if (!/^[0-9a-f-]{32,40}$/i.test(deviceId)) {
      return reply({ error: "device_id_required" }, 400);
    }
    const analysisKey = String(input.analysis_key ?? "");
    const deviceHash = await hashDeviceId(deviceId);
    if (/^[0-9a-f]{8,32}$/i.test(analysisKey)) {
      const cached = await readAnalysisCache(deviceHash, analysisKey);
      if (cached != null) {
        return reply({
          source_post_id: sourcePostId,
          ...cached,
          analysis_source: "ai_server_cache",
        });
      }
    }
    if (!await consumeQuota(deviceId)) {
      return reply({ error: "daily_limit_reached" }, 429);
    }
    quotaReserved = true;

    const videoEvidence = await fetchVideoEvidence(
      sharedPage?.canonical_url ?? String(input.url ?? ""),
    );

    const content: Array<Record<string, unknown>> = [{
      type: "input_text",
      text: [
        `最優先の投稿文・コメント:\n${[
          cleanSharedText(input.text, sharedPage),
          sharedPage?.description,
        ].filter(Boolean).join("\n")}`,
        `補助根拠の端末OCR（投稿文・コメントと矛盾する場合は採用禁止）:\n${String(input.ocr_text ?? "")}`,
        `動画の音声文字起こし:\n${videoEvidence?.transcript ?? ""}`,
        `動画取得元のタイトル・説明:\n${[
          videoEvidence?.source_title,
          videoEvidence?.source_description,
        ].filter(Boolean).join("\n")}`,
        `共有URL:\n${String(input.url ?? "")}`,
        `URLから取得した投稿情報:\n${JSON.stringify(
          sharedPage == null ? {} : { ...sharedPage, image_urls: undefined },
        )}`,
        `端末候補:\n${JSON.stringify(input.local_candidates ?? [])}`,
      ].join("\n\n"),
    }];
    let analysisImageIndex = 0;
    for (let index = 0; index < suppliedImages.length; index++) {
      const image = suppliedImages[index];
      const originalIndex = suppliedImageIndexes[index] ?? analysisImageIndex;
      content.push({
        type: "input_text",
        text: `画像${originalIndex}（ユーザーが選択した解析対象）`,
      });
      content.push({ type: "input_image", image_url: image, detail: "high" });
      analysisImageIndex++;
    }
    // SNSの複数画像投稿は共有拡張へ画像本体を渡さないことがある。
    // 公開ページ内の投稿画像だけを同じ1回の解析へ追加する。
    const fetchedCandidates = selectedImagesOnly
      ? []
      : await fetchSocialImages(
        (sharedPage?.image_urls ?? []).slice(0, maxSocialImages),
        sharedPage?.service ?? null,
      );
    const suppliedFingerprints = new Set(suppliedImages.map(imageFingerprint));
    const orderedFetchedCandidates = sharedPage?.service === "instagram" &&
        suppliedImages.length === 1 && fetchedCandidates.length > 1
      ? fetchedCandidates.slice(1)
      : fetchedCandidates;
    const fetchedSocialImages = orderedFetchedCandidates
      .filter((image) => !suppliedFingerprints.has(imageFingerprint(image)))
      .slice(0, Math.max(0, maxSocialImages - suppliedImages.length));
    for (const image of fetchedSocialImages) {
      content.push({
        type: "input_text",
        text: `画像${analysisImageIndex}（SNSカルーセル・投稿順）`,
      });
      content.push({ type: "input_image", image_url: image, detail: "high" });
      analysisImageIndex++;
    }
    const videoFrames = (videoEvidence?.frames ?? [])
      .slice(0, Math.max(0, maxAnalysisImages - analysisImageIndex));
    for (const frame of videoFrames) {
      content.push({
        type: "input_text",
        text: `画像${analysisImageIndex}（動画 ${frame.timestamp_seconds}秒地点）`,
      });
      content.push({ type: "input_image", image_url: frame.data_url, detail: "high" });
      analysisImageIndex++;
    }

    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: Deno.env.get("OPENAI_MODEL") ?? "gpt-5.6-luna",
        store: false,
        reasoning: { effort: "low" },
        max_output_tokens: 8000,
        instructions:
          "SNS投稿を日本語の構造化レシピへ整理してください。入力された全画像を番号順に必ず確認してください。" +
          "根拠の優先順位は、ユーザー修正、投稿文・キャプション、明瞭な画像字幕、投稿者の固定コメント、音声文字起こし、AI推測の順です。上位根拠と矛盾する下位根拠で上書きしないでください。" +
          "1投稿に完成料理が複数ある場合はrecipesを料理ごとに分けます。一方、本体、出汁、タレ、漬けだれ、衣、トッピングなど同じ完成料理を構成する別作業は、別recipeにせず同じrecipeのpartsへ分けてください。" +
          "材料は画面に出た『小さじ1』『1/2個』等をoriginal_textへ残し、数値化できる場合だけamountとunitを設定します。適量、少々、いつもの量など曖昧な表現は推測せずoriginal_textへそのまま残しscalable=falseにしてください。" +
          "工程は実際の表示・音声の順番を保ち、前後の画像や別料理を混ぜません。加熱・待ち時間が明記された場合だけduration_secondsを設定します。" +
          "一瞬だけの文字、装飾フォント、背景と同化した字幕、音声だけの分量、料理が高速に切り替わる箇所は確信度を下げ、読めない内容を補完せずneeds_review_fieldsへ具体的に記載してください。" +
          "投稿文に完全な材料・工程があれば画像より優先します。ただし画像にしかない情報も追加し、矛盾はwarningsに残してください。取得できない動画内容は推測しません。" +
          "evidenceには画像番号・時刻・投稿文抜粋などの根拠を登録し、各材料と工程のevidence_indexから対応させてください。画像番号は入力で示した0始まり番号です。" +
          "category、cuisine、main_ingredient、methodは料理ごとに個別判断し、複数料理へ同じ値を機械的にコピーしないでください。" +
          "アレルゲンは明記または一般的な原材料として高い確度で含むものだけを列挙し、安全を保証しないでください。栄養値は十分な分量がある場合だけ概算し、不足時はnullにしてください。" +
          "後方互換用candidatesは常に空配列にしてください。recipeを特定できない場合はrecipesを空にし、raw_summaryへ不足している根拠を書いてください。",
        input: [{ role: "user", content }],
        text: { verbosity: "low", format: recipeSchema },
      }),
    });
    if (!response.ok) {
      const detail = (await response.text()).slice(0, 1000);
      console.error("openai_failed", response.status, detail);
      await refundQuota(deviceId);
      quotaReserved = false;
      return reply({ error: "openai_failed" }, 502);
    }
    const value = await response.json();
    const output = value.output
      ?.flatMap((item: { content?: unknown[] }) => item.content ?? [])
      .find((part: { type?: string }) => part.type === "output_text") as
      | { text?: string }
      | undefined;
    if (!output?.text) {
      await refundQuota(deviceId);
      quotaReserved = false;
      return reply({ error: "empty_ai_response" }, 502);
    }
    const parsedOutput = sanitizeParsedOutput(JSON.parse(output.text), sharedPage);
    const successfulResult = {
      source_post_id: sourcePostId,
      ...parsedOutput,
      analysis_source: videoFrames.length > 0
        ? "ai_video_frames_and_audio"
        : sharedPage?.is_photo_post === true
        ? (selectedImagesOnly && suppliedImages.length > 0
          ? `ai_${sharedPage.service}_selected_images`
          : fetchedSocialImages.length > 0
          ? `ai_${sharedPage.service}_photos`
          : `ai_${sharedPage.service}_text_only`)
        : "ai",
      shared_media: sharedMedia(
        sharedPage,
        [...fetchedSocialImages, ...videoFrames.map((frame) => frame.data_url)],
      ),
    };
    if (/^[0-9a-f]{8,32}$/i.test(analysisKey)) {
      await writeAnalysisCache(deviceHash, analysisKey, parsedOutput);
    }
    quotaReserved = false;
    return reply(successfulResult);
  } catch (error) {
    if (quotaReserved && deviceId) await refundQuota(deviceId);
    console.error("analysis_failed", error);
    return reply({ error: "analysis_failed" }, 500);
  }
});

function sharedMedia(sharedPage: SharedPage | null, images: string[]) {
  if (sharedPage == null) return null;
  return {
    is_photo_post: sharedPage.is_photo_post,
    photo_access: images.length > 0 ? "available" : sharedPage.photo_access,
    image_count: images.length,
    thumbnail_data_url: images[0] ?? null,
    image_data_urls: images,
  };
}

function imageFingerprint(dataUrl: string) {
  const comma = dataUrl.indexOf(",");
  const body = comma >= 0 ? dataUrl.slice(comma + 1) : dataUrl;
  // 完全一致画像の重複除外用。暗号用途ではない。
  let hash = 2166136261;
  for (let index = 0; index < body.length; index++) {
    hash ^= body.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return `${body.length}:${hash >>> 0}`;
}

const recipeSchema = {
  type: "json_schema",
  name: "pinlogy_recipes",
  strict: true,
  schema: {
    type: "object",
    additionalProperties: false,
    required: ["raw_summary", "candidates", "recipes"],
    properties: {
      raw_summary: { type: "string" },
      candidates: {
        type: "array",
        maxItems: 0,
        items: { type: "object", additionalProperties: false, properties: {}, required: [] },
      },
      recipes: {
        type: "array",
        maxItems: 8,
        items: {
          type: "object",
          additionalProperties: false,
          required: [
            "title", "description", "servings", "total_minutes", "difficulty",
            "category", "cuisine", "main_ingredient", "method",
            "cover_image_index", "parts", "evidence", "allergens", "warnings",
            "needs_review_fields", "nutrition"
          ],
          properties: {
            title: { type: "string" },
            description: { type: ["string", "null"] },
            servings: { type: ["number", "null"], minimum: 0.1, maximum: 100 },
            total_minutes: { type: ["integer", "null"], minimum: 0, maximum: 2880 },
            difficulty: { type: ["string", "null"], enum: ["かんたん", "ふつう", "本格的", null] },
            category: { type: ["string", "null"] },
            cuisine: { type: ["string", "null"] },
            main_ingredient: { type: ["string", "null"] },
            method: { type: ["string", "null"] },
            cover_image_index: {
              type: ["integer", "null"],
              minimum: 0,
              maximum: maxAnalysisImages - 1,
            },
            parts: {
              type: "array",
              minItems: 1,
              maxItems: 12,
              items: {
                type: "object",
                additionalProperties: false,
                required: ["name", "ingredients", "steps"],
                properties: {
                  name: { type: "string" },
                  ingredients: {
                    type: "array",
                    maxItems: 80,
                    items: {
                      type: "object",
                      additionalProperties: false,
                      required: ["name", "amount", "unit", "original_text", "note", "scalable", "evidence_index", "confidence_percent"],
                      properties: {
                        name: { type: "string" },
                        amount: { type: ["number", "null"] },
                        unit: { type: ["string", "null"] },
                        original_text: { type: ["string", "null"] },
                        note: { type: ["string", "null"] },
                        scalable: { type: "boolean" },
                        evidence_index: { type: ["integer", "null"], minimum: 0, maximum: 99 },
                        confidence_percent: { type: "integer", minimum: 0, maximum: 100 },
                      },
                    },
                  },
                  steps: {
                    type: "array",
                    maxItems: 80,
                    items: {
                      type: "object",
                      additionalProperties: false,
                      required: ["order", "instruction", "duration_seconds", "evidence_index", "confidence_percent"],
                      properties: {
                        order: { type: "integer", minimum: 1, maximum: 100 },
                        instruction: { type: "string" },
                        duration_seconds: { type: ["integer", "null"], minimum: 0, maximum: 86400 },
                        evidence_index: { type: ["integer", "null"], minimum: 0, maximum: 99 },
                        confidence_percent: { type: "integer", minimum: 0, maximum: 100 },
                      },
                    },
                  },
                },
              },
            },
            evidence: {
              type: "array",
              maxItems: 100,
              items: {
                type: "object",
                additionalProperties: false,
                required: ["kind", "label", "image_index", "timestamp_seconds", "excerpt", "confidence_percent"],
                properties: {
                  kind: { type: "string", enum: ["image", "video", "caption", "author_comment", "audio", "aiInference"] },
                  label: { type: "string" },
                  image_index: { type: ["integer", "null"], minimum: 0, maximum: maxAnalysisImages - 1 },
                  timestamp_seconds: { type: ["integer", "null"], minimum: 0, maximum: 21600 },
                  excerpt: { type: ["string", "null"] },
                  confidence_percent: { type: "integer", minimum: 0, maximum: 100 },
                },
              },
            },
            allergens: { type: "array", maxItems: 30, items: { type: "string" } },
            warnings: { type: "array", maxItems: 30, items: { type: "string" } },
            needs_review_fields: { type: "array", maxItems: 50, items: { type: "string" } },
            nutrition: {
              type: "object",
              additionalProperties: false,
              required: ["calories", "protein_grams", "fat_grams", "carbohydrate_grams"],
              properties: {
                calories: { type: ["integer", "null"], minimum: 0, maximum: 10000 },
                protein_grams: { type: ["number", "null"], minimum: 0, maximum: 1000 },
                fat_grams: { type: ["number", "null"], minimum: 0, maximum: 1000 },
                carbohydrate_grams: { type: ["number", "null"], minimum: 0, maximum: 2000 },
              },
            },
          },
        },
      },
    },
  },
};

function validImages(value: unknown) {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item): item is string =>
      typeof item === "string" && /^data:image\/(jpeg|png|webp);base64,/i.test(item)
    )
    .slice(0, maxSocialImages);
}

function validImageIndexes(value: unknown) {
  if (!Array.isArray(value)) return [];
  return value
    .map((item) => Number(item))
    .filter((item) =>
      Number.isInteger(item) && item >= 0 && item < maxSocialImages
    )
    .slice(0, maxSocialImages);
}

function isAllowedSocialUrl(url: URL) {
  const host = url.hostname.toLowerCase();
  return host === "tiktok.com" || host.endsWith(".tiktok.com") ||
    host === "instagram.com" || host.endsWith(".instagram.com");
}

async function fetchSocialPage(initial: URL) {
  let current = initial;
  for (let redirects = 0; redirects <= 5; redirects++) {
    if (!isAllowedSocialUrl(current)) throw new Error("untrusted_redirect");
    const response = await fetch(current, {
      redirect: "manual",
      headers: {
        "User-Agent":
          "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/125 Mobile Safari/537.36",
        "Accept-Language": "ja,en;q=0.8",
      },
      signal: AbortSignal.timeout(8000),
    });
    if (response.status < 300 || response.status >= 400) {
      return { response, finalUrl: current.toString() };
    }
    const location = response.headers.get("location");
    if (!location) throw new Error("redirect_without_location");
    current = new URL(location, current);
  }
  throw new Error("too_many_redirects");
}

type SharedPage = {
  service: "tiktok" | "instagram";
  canonical_url: string;
  title: string | null;
  description: string | null;
  oembed?: Record<string, unknown>;
  is_photo_post: boolean;
  photo_access: "available" | "unavailable" | "not_applicable";
  image_urls: string[];
  fetch_status: number;
};

type VideoEvidence = {
  duration_seconds: number;
  transcript: string;
  source_title: string;
  source_description: string;
  frames: Array<{ data_url: string; timestamp_seconds: number }>;
};

async function fetchVideoEvidence(rawUrl: string): Promise<VideoEvidence | null> {
  if (!rawUrl) return null;
  let source: URL;
  try {
    source = new URL(rawUrl);
  } catch {
    return null;
  }
  if (!isAllowedSocialUrl(source)) return null;
  const likelyVideo = /\/video\/\d+/i.test(source.pathname) ||
    /\/(reel|p)\/[^/]+/i.test(source.pathname);
  if (!likelyVideo) return null;
  const workerUrl = (Deno.env.get("VIDEO_WORKER_URL") ?? "").trim();
  const workerSecret = (Deno.env.get("VIDEO_WORKER_SECRET") ?? "").trim();
  if (!workerUrl || !workerSecret) {
    console.warn("video_worker_not_configured");
    return null;
  }
  try {
    const endpoint = new URL(
      "/extract",
      workerUrl.endsWith("/") ? workerUrl : `${workerUrl}/`,
    );
    if (endpoint.protocol !== "https:") throw new Error("worker_https_required");
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${workerSecret}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ url: source.toString() }),
      signal: AbortSignal.timeout(230_000),
    });
    if (!response.ok) {
      console.warn(
        "video_worker_failed",
        response.status,
        (await response.text()).slice(0, 300),
      );
      return null;
    }
    const decoded = await response.json();
    const frames = Array.isArray(decoded.frames)
      ? decoded.frames.filter((frame: unknown) => {
        if (frame == null || typeof frame !== "object") return false;
        const record = frame as Record<string, unknown>;
        return typeof record.data_url === "string" &&
          /^data:image\/jpeg;base64,/i.test(record.data_url) &&
          Number.isFinite(Number(record.timestamp_seconds));
      }).slice(0, maxVideoFrames).map((frame: Record<string, unknown>) => ({
        data_url: String(frame.data_url),
        timestamp_seconds: Math.max(0, Math.round(Number(frame.timestamp_seconds))),
      }))
      : [];
    console.info(
      "video_worker_resolved",
      `frames=${frames.length}`,
      `transcript=${String(decoded.transcript ?? "").length}`,
    );
    return {
      duration_seconds: Math.max(0, Math.round(Number(decoded.duration_seconds ?? 0))),
      transcript: String(decoded.transcript ?? "").slice(0, 12000),
      source_title: String(decoded.source_title ?? "").slice(0, 1000),
      source_description: String(decoded.source_description ?? "").slice(0, 8000),
      frames,
    };
  } catch (error) {
    console.warn("video_worker_failed", String(error));
    return null;
  }
}

async function enrichSharedUrl(rawUrl: string): Promise<SharedPage | null> {
  if (!rawUrl) return null;
  try {
    const initial = new URL(rawUrl);
    if (!isAllowedSocialUrl(initial)) return null;
    const { response, finalUrl } = await fetchSocialPage(initial);
    const final = new URL(finalUrl);
    const isTikTok = final.hostname.toLowerCase().endsWith("tiktok.com");
    const isInstagram = final.hostname.toLowerCase().endsWith("instagram.com");
    const service = isTikTok ? "tiktok" : "instagram";
    const isPhotoPost = (isTikTok && /\/photo\/\d+/.test(final.pathname)) ||
      (isInstagram && /\/(p|reel)\//.test(final.pathname));
    if (!response.ok) {
      console.warn("shared_page_http_failed", response.status, final.hostname);
      return {
        service,
        canonical_url: finalUrl,
        title: null,
        description: null,
        is_photo_post: isPhotoPost,
        photo_access: isPhotoPost ? "unavailable" : "not_applicable",
        image_urls: [],
        fetch_status: response.status,
      };
    }
    const html = (await response.text()).slice(0, 2_000_000);
    // 通常ページは代表画像しか含まない場合があるため、Instagram公式の
    // 公開埋め込みページも読み、カルーセルを投稿順で最大10枚まで復元する。
    const instagramEmbedHtml = isInstagram
      ? await fetchInstagramEmbedHtml(final)
      : null;
    let imageUrls = isTikTok
      ? (isPhotoPost ? extractTikTokPhotoUrls(html) : [])
      : mergeInstagramImages(
        extractInstagramPhotoUrls(instagramEmbedHtml ?? ""),
        extractInstagramPhotoUrls(html),
      );
    let externalDescription: string | null = null;
    if (isInstagram && isPhotoPost && imageUrls.length <= 1) {
      if (hasBrightDataInstagramAccess()) {
        // 9枚取得に成功したv28の取得経路を固定して使用する。
        const external = await fetchBrightDataInstagramPostV28(final);
        if (external != null) {
          imageUrls = mergeInstagramImages(external.imageUrls, imageUrls);
          externalDescription = external.description;
        }
      } else {
        // 外部取得を設定していない開発環境では、従来の公開URL探索を維持する。
        const indexed = await fetchInstagramIndexedImages(final);
        imageUrls = mergeInstagramImages(indexed, imageUrls);
      }
    }
    const rawDescription = externalDescription ??
      meta(html, "og:description") ??
      meta(html, "description") ??
      meta(instagramEmbedHtml ?? "", "og:description") ??
      meta(instagramEmbedHtml ?? "", "description");
    console.info(
      "shared_media_resolved",
      service,
      `images=${imageUrls.length}`,
      `embed=${instagramEmbedHtml != null}`,
    );
    const metadata: SharedPage = {
      service,
      canonical_url: finalUrl,
      // Instagramのog:titleは投稿者名であり、店名の根拠にはしない。
      title: isInstagram ? null : meta(html, "og:title") ?? pageTitle(html),
      description: isInstagram
        ? instagramCaption(rawDescription)
        : rawDescription,
      is_photo_post: isPhotoPost,
      photo_access: isPhotoPost
        ? (imageUrls.length > 0 ? "available" : "unavailable")
        : "not_applicable",
      image_urls: imageUrls,
      fetch_status: response.status,
    };

    if (isTikTok) {
      try {
        const endpoint = new URL("https://www.tiktok.com/oembed");
        endpoint.searchParams.set("url", finalUrl);
        const embedResponse = await fetch(endpoint, {
          redirect: "error",
          headers: { "User-Agent": "Pinlogy/1.0" },
          signal: AbortSignal.timeout(8000),
        });
        if (embedResponse.ok) {
          const embed = await embedResponse.json();
          metadata.oembed = {
            title: embed.title,
            author_name: embed.author_name,
            author_url: embed.author_url,
          };
        }
      } catch (error) {
        console.warn("tiktok_oembed_failed", String(error));
      }
    }
    return metadata;
  } catch (error) {
    console.warn("shared_url_enrichment_failed", String(error));
    return null;
  }
}

async function fetchInstagramEmbedHtml(postUrl: URL) {
  try {
    const path = postUrl.pathname.replace(/\/+$/, "");
    if (!/^\/(p|reel)\/[^/]+$/i.test(path)) return null;
    const embedUrl = new URL(`${path}/embed/captioned/`, postUrl.origin);
    const { response } = await fetchSocialPage(embedUrl);
    if (!response.ok) {
      console.warn("instagram_embed_http_failed", response.status);
      return null;
    }
    return (await response.text()).slice(0, 3_000_000);
  } catch (error) {
    console.warn("instagram_embed_failed", String(error));
    return null;
  }
}

/// Instagramの共有URLには、現在表示していた画像番号が
/// `img_index=10` のように付くことがある。通常HTML・埋め込みHTMLが
/// その1枚だけを代表画像として返す場合に備え、1〜10枚目を投稿順で
/// 明示的に問い合わせる。AI APIは呼ばず、公開ページの画像取得だけを行う。
async function fetchInstagramIndexedImages(postUrl: URL) {
  const path = postUrl.pathname.replace(/\/+$/, "");
  if (!/^\/(p|reel)\/[^/]+$/i.test(path)) return [];

  const results = await Promise.all(
    Array.from({ length: maxSocialImages }, async (_, offset) => {
      const index = offset + 1;
      try {
        const indexedUrl = new URL(`${path}/`, postUrl.origin);
        indexedUrl.searchParams.set("img_index", String(index));
        const { response } = await fetchSocialPage(indexedUrl);
        if (!response.ok) return [] as string[];
        const indexedHtml = (await response.text()).slice(0, 2_000_000);
        const representative = meta(indexedHtml, "og:image");
        return mergeInstagramImages(
          representative && isAllowedInstagramImage(representative)
            ? [representative]
            : [],
          extractInstagramPhotoUrls(indexedHtml),
        );
      } catch (error) {
        console.warn("instagram_indexed_image_failed", index, String(error));
        return [] as string[];
      }
    }),
  );

  const ordered = mergeInstagramImages(...results);
  console.info("instagram_indexed_images_resolved", `images=${ordered.length}`);
  return ordered;
}

type ExternalInstagramPost = {
  imageUrls: string[];
  description: string | null;
};

/// v28で成功したデータ解釈を維持しつつ、現在のBright Data仕様に合わせて
/// snapshotがreadyになるまで待つ。202を1枚フォールバック扱いにしない。
async function fetchBrightDataInstagramPostV28(
  postUrl: URL,
): Promise<ExternalInstagramPost | null> {
  const token = (Deno.env.get("BRIGHT_DATA_API_TOKEN") ?? "").trim();
  if (!token) return null;

  const path = postUrl.pathname.replace(/\/+$/, "");
  if (!/^\/(p|reel)\/[^/]+$/i.test(path)) return null;
  const canonicalUrl = new URL(`${path}/`, postUrl.origin);
  const endpoint = new URL("https://api.brightdata.com/datasets/v3/trigger");
  endpoint.searchParams.set("dataset_id", "gd_lk5ns7kz21pck8jpis");
  endpoint.searchParams.set("include_errors", "true");

  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify([{ url: canonicalUrl.toString() }]),
      signal: AbortSignal.timeout(15_000),
    });
    if (!response.ok) {
      console.warn("bright_data_instagram_v28_http_failed", response.status);
      return null;
    }
    const trigger = await response.json();
    const snapshotId = String(trigger?.snapshot_id ?? "").trim();
    // Bright Dataの現行IDは `sd_...`。英数字・`_`・`-`だけを許可し、
    // URL組み立て時の安全性を保ったまま新旧snapshot IDへ対応する。
    if (!/^[A-Za-z0-9_-]{8,128}$/.test(snapshotId)) {
      console.warn("bright_data_instagram_snapshot_missing");
      return null;
    }
    console.info("bright_data_instagram_snapshot_started", snapshotId);

    // 5秒間隔、最大90秒。完了前に代表画像へ戻さず、readyだけを採用する。
    for (let attempt = 0; attempt < 18; attempt++) {
      if (attempt > 0) await delay(5_000);
      const progress = await fetch(
        `https://api.brightdata.com/datasets/v3/progress/${encodeURIComponent(snapshotId)}`,
        {
          headers: { "Authorization": `Bearer ${token}` },
          signal: AbortSignal.timeout(12_000),
        },
      );
      if (!progress.ok) {
        console.warn("bright_data_instagram_progress_failed", progress.status);
        continue;
      }
      const progressJson = await progress.json();
      const status = String(progressJson?.status ?? "").toLowerCase();
      if (status === "failed") {
        console.warn(
          "bright_data_instagram_snapshot_failed",
          String(progressJson?.error_message ?? "unknown").slice(0, 300),
        );
        return null;
      }
      if (status !== "ready") continue;

      const snapshot = await fetch(
        `https://api.brightdata.com/datasets/v3/snapshot/${encodeURIComponent(snapshotId)}?format=json`,
        {
          headers: { "Authorization": `Bearer ${token}` },
          signal: AbortSignal.timeout(20_000),
        },
      );
      if (!snapshot.ok) {
        console.warn("bright_data_instagram_snapshot_http_failed", snapshot.status);
        return null;
      }
      const result = parseExternalInstagramPost(await snapshot.json());
      console.info(
        "bright_data_instagram_snapshot_resolved",
        `images=${result?.imageUrls.length ?? 0}`,
      );
      return result;
    }
    console.warn("bright_data_instagram_snapshot_timeout", snapshotId);
    return null;
  } catch (error) {
    console.warn("bright_data_instagram_v28_failed", String(error));
    return null;
  }
}

function parseExternalInstagramPost(decoded: unknown): ExternalInstagramPost | null {
  const rows = Array.isArray(decoded) ? decoded : [decoded];
  const row = rows.find((value) => value != null && typeof value === "object");
  if (row == null || typeof row !== "object") return null;
  const record = row as Record<string, unknown>;
  const images: string[] = [];

  if (Array.isArray(record.photos)) {
    for (const value of record.photos) addExternalInstagramUrl(value, images);
  }
  if (Array.isArray(record.post_content)) {
    const ordered = [...record.post_content].sort((left, right) =>
      externalImageIndex(left) - externalImageIndex(right)
    );
    for (const value of ordered) addExternalInstagramUrl(value, images);
  }
  if (Array.isArray(record.images)) {
    for (const value of record.images) addExternalInstagramUrl(value, images);
  }
  if (images.length === 0) addExternalInstagramUrl(record.thumbnail, images);

  const authoritativeText = collectExternalInstagramText(record);
  return {
    imageUrls: images.slice(0, maxSocialImages),
    description: authoritativeText || null,
  };
}

/// 投稿本文と取得できたコメントだけを高優先根拠として渡す。
/// 画像URLやユーザー名などの無関係な文字列は混ぜない。
function collectExternalInstagramText(record: Record<string, unknown>) {
  const output: string[] = [];
  const add = (value: unknown) => {
    if (typeof value !== "string") return;
    const text = value.trim();
    if (text.length < 2 || /^https?:\/\//i.test(text)) return;
    if (!output.includes(text)) output.push(text);
  };
  for (const key of ["description", "caption", "post_text", "text"]) {
    add(record[key]);
  }
  const comments = record.comments;
  if (Array.isArray(comments)) {
    for (const comment of comments.slice(0, 50)) {
      if (typeof comment === "string") {
        add(comment);
      } else if (comment != null && typeof comment === "object") {
        const value = comment as Record<string, unknown>;
        add(value.text ?? value.comment ?? value.body ?? value.content);
      }
    }
  }
  return output.join("\n").slice(0, 12_000);
}

function delay(milliseconds: number) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

function hasBrightDataInstagramAccess() {
  return (Deno.env.get("BRIGHT_DATA_API_TOKEN") ?? "").trim().length > 0;
}

/// 通常の公開HTMLで0〜1枚しか取得できない場合だけ利用する予備経路。
/// トークンはSupabase Secretsから読み、クライアントやログへ公開しない。
async function fetchBrightDataInstagramPost(
  postUrl: URL,
): Promise<ExternalInstagramPost | null> {
  const token = (Deno.env.get("BRIGHT_DATA_API_TOKEN") ?? "").trim();
  if (!token) return null;

  const path = postUrl.pathname.replace(/\/+$/, "");
  if (!/^\/(p|reel)\/[^/]+$/i.test(path)) return null;
  const canonicalUrl = new URL(`${path}/`, postUrl.origin);
  const endpoint = new URL("https://api.brightdata.com/datasets/v3/scrape");
  endpoint.searchParams.set("dataset_id", "gd_lk5ns7kz21pck8jpis");
  endpoint.searchParams.set("include_errors", "true");
  endpoint.searchParams.set("format", "json");

  try {
    const response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ input: [{ url: canonicalUrl.toString() }] }),
      // アプリ側のプレビュー取得期限より先に必ず応答へ戻す。
      signal: AbortSignal.timeout(14_000),
    });
    if (response.status === 202) {
      console.info("bright_data_instagram_pending");
      return null;
    }
    if (!response.ok) {
      console.warn("bright_data_instagram_http_failed", response.status);
      return null;
    }
    const decoded = await response.json();
    const rows = Array.isArray(decoded) ? decoded : [decoded];
    const row = rows.find((value) => value != null && typeof value === "object");
    if (row == null || typeof row !== "object") return null;
    const record = row as Record<string, unknown>;
    const images: string[] = [];

    const photos = record.photos;
    if (Array.isArray(photos)) {
      for (const value of photos) addExternalInstagramUrl(value, images);
    }

    const postContent = record.post_content;
    if (Array.isArray(postContent)) {
      const ordered = [...postContent].sort((left, right) =>
        externalImageIndex(left) - externalImageIndex(right)
      );
      for (const value of ordered) addExternalInstagramUrl(value, images);
    }

    const imageRecords = record.images;
    if (Array.isArray(imageRecords)) {
      for (const value of imageRecords) addExternalInstagramUrl(value, images);
    }

    if (images.length === 0) addExternalInstagramUrl(record.thumbnail, images);
    const description = typeof record.description === "string"
      ? record.description.trim().slice(0, 4000)
      : null;
    console.info("bright_data_instagram_resolved", `images=${images.length}`);
    return {
      imageUrls: images.slice(0, maxSocialImages),
      description: description && description.length > 0 ? description : null,
    };
  } catch (error) {
    console.warn("bright_data_instagram_failed", String(error));
    return null;
  }
}

function externalImageIndex(value: unknown) {
  if (value == null || typeof value !== "object") return 1_000_000;
  const index = Number((value as Record<string, unknown>).index);
  return Number.isInteger(index) ? index : 1_000_000;
}

function addExternalInstagramUrl(value: unknown, output: string[]) {
  if (output.length >= maxSocialImages || value == null) return;
  const raw = typeof value === "string"
    ? value
    : typeof value === "object"
    ? (value as Record<string, unknown>).url
    : null;
  if (typeof raw !== "string") return;
  const url = normalizeEmbeddedJson(raw.trim());
  if (isAllowedInstagramImage(url) && !hasSameImage(output, url)) {
    output.push(url);
  }
}

function mergeInstagramImages(...groups: string[][]) {
  const merged: string[] = [];
  for (const group of groups) {
    for (const url of group) {
      if (!hasSameImage(merged, url)) merged.push(url);
      if (merged.length >= maxSocialImages) return merged;
    }
  }
  return merged;
}

function instagramCaption(value: string | null) {
  if (!value) return null;
  const cleaned = decodeHtml(value).trim();
  // 例: "123 likes ... - user on Instagram: \"投稿本文\""
  const quoted = cleaned.match(/\bon Instagram\s*:\s*[“\"]([\s\S]*?)[”\"]\s*$/i)?.[1];
  if (quoted?.trim()) return quoted.trim().slice(0, 4000);
  if (/^(?:Instagram|Login\s*[•|-]\s*Instagram)$/i.test(cleaned)) return null;
  if (/\bon Instagram\b/i.test(cleaned) && !/[#〒]|(?:都|道|府|県|市|区)/.test(cleaned)) {
    return null;
  }
  return cleaned.slice(0, 4000);
}

function cleanSharedText(value: unknown, sharedPage: SharedPage | null) {
  const text = String(value ?? "").trim();
  if (sharedPage?.service !== "instagram") return text;
  return text.split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .filter((line) => !/^Instagramの投稿$/i.test(line))
    .filter((line) => !/\bon Instagram\b/i.test(line))
    .filter((line) => !/^[^\n]{1,80}\s*[•|｜-]\s*Instagram/i.test(line))
    .join("\n");
}

function sanitizeParsedOutput(
  value: unknown,
  sharedPage: SharedPage | null,
): Record<string, unknown> {
  if (value == null || typeof value !== "object") {
    throw new Error("invalid_ai_output");
  }
  const output = value as Record<string, unknown>;
  if (!Array.isArray(output.candidates)) return output;
  const filtered = output.candidates.filter((candidate) => {
    if (candidate == null || typeof candidate !== "object") return false;
    const name = String((candidate as Record<string, unknown>).name ?? "").trim();
    if (name.length < 2) return false;
    if (/^(Instagram|TikTok|共有された投稿|Instagramの投稿)$/i.test(name)) return false;
    if (/\bon Instagram\b/i.test(name)) return false;
    if (/^[＠@]?[A-Za-z0-9._]{2,30}$/.test(name) && sharedPage?.service === "instagram") {
      return false;
    }
    return true;
  });
  // The model may mention the same store once from the caption and once from
  // an image. Keep one candidate per real place without collapsing distinct
  // branches or stores from the same carousel.
  const unique = new Map<string, Record<string, unknown>>();
  for (const candidate of filtered) {
    const record = candidate as Record<string, unknown>;
    const key = candidateIdentity(record);
    const previous = unique.get(key);
    if (previous == null || candidateScore(record) > candidateScore(previous)) {
      unique.set(key, record);
    }
  }
  output.candidates = [...unique.values()];
  return output;
}

function candidateIdentity(candidate: Record<string, unknown>) {
  const normalize = (value: unknown) => String(value ?? "")
    .normalize("NFKC")
    .toLowerCase()
    .replace(/[\s\u3000・･,，.。'’"“”()（）\-ー]/g, "");
  const name = normalize(candidate.name);
  const address = normalize(candidate.address ?? candidate.postAddress);
  if (address) return `${name}|${address}`;
  const hasRawCoordinates = candidate.latitude != null && candidate.longitude != null;
  const latitude = Number(candidate.latitude);
  const longitude = Number(candidate.longitude);
  if (hasRawCoordinates && Number.isFinite(latitude) && Number.isFinite(longitude)) {
    return `${name}|${latitude.toFixed(5)},${longitude.toFixed(5)}`;
  }
  // Name-only candidates are merged only when their normalized names match.
  return `name:${name}`;
}

function candidateScore(candidate: Record<string, unknown>) {
  const confidence = Number(candidate.confidencePercent) || 0;
  const hasAddress = String(candidate.address ?? "").trim().length > 0 ? 20 : 0;
  const hasCoordinates = candidate.latitude != null && candidate.longitude != null &&
      Number.isFinite(Number(candidate.latitude)) &&
      Number.isFinite(Number(candidate.longitude))
    ? 20
    : 0;
  return confidence + hasAddress + hasCoordinates;
}

/// Instagramの公開HTMLから、投稿本体の代表画像とカルーセル画像だけを抽出する。
/// 非公開・ログイン必須投稿は無理に回避せず、取得不可として返す。
function extractInstagramPhotoUrls(html: string) {
  const candidates: string[] = [];
  const representative = meta(html, "og:image");

  const scriptPattern = /<script[^>]*>([\s\S]*?)<\/script>/gi;
  for (const match of html.matchAll(scriptPattern)) {
    const decoded = normalizeEmbeddedJson(match[1] ?? "");
    if (!looksLikeInstagramPostMedia(decoded)) continue;
    try {
      collectInstagramPostImages(JSON.parse(decoded), candidates);
    } catch {
      collectInstagramUrlsFromMarkedBlocks(decoded, candidates);
    }
    if (candidates.length >= maxSocialImages) break;
  }
  if (candidates.length === 0 && representative &&
    isAllowedInstagramImage(representative)) {
    candidates.push(representative);
  }
  return candidates.slice(0, maxSocialImages);
}

function looksLikeInstagramPostMedia(value: string) {
  return value.includes("carousel_media") ||
    value.includes("edge_sidecar_to_children") ||
    value.includes("shortcode_media") ||
    value.includes("gql_data") ||
    value.includes("xdt_api__v1__media__shortcode__web_info") ||
    value.includes("image_versions2");
}

function collectInstagramPostImages(
  value: unknown,
  output: string[],
  insidePostMedia = false,
) {
  if (output.length >= maxSocialImages || value == null) return;
  if (typeof value === "string") {
    const decoded = normalizeEmbeddedJson(value);
    if (!looksLikeInstagramPostMedia(decoded)) return;
    try {
      collectInstagramPostImages(JSON.parse(decoded), output, insidePostMedia);
    } catch {
      collectInstagramUrlsFromMarkedBlocks(decoded, output);
    }
    return;
  }
  if (Array.isArray(value)) {
    for (const item of value) {
      collectInstagramPostImages(item, output, insidePostMedia);
    }
    return;
  }
  if (typeof value !== "object") return;
  const record = value as Record<string, unknown>;
  const mediaKeys = [
    "carousel_media",
    "edge_sidecar_to_children",
    "shortcode_media",
    "gql_data",
    "xdt_api__v1__media__shortcode__web_info",
    "image_versions2",
  ];
  const isMediaNode = insidePostMedia || mediaKeys.some((key) => key in record);
  if (isMediaNode) {
    for (const key of [
      "display_url",
      "media_url",
      "image_url",
      "thumbnail_url",
      "url",
    ]) {
      addInstagramImage(record[key], output);
    }
    const candidates = record.candidates;
    if (Array.isArray(candidates)) {
      for (const candidate of candidates) {
        if (candidate && typeof candidate === "object") {
          addInstagramImage(
            (candidate as Record<string, unknown>).url,
            output,
          );
          if (output.length >= maxSocialImages) return;
        }
      }
    }
  }
  for (const [key, nested] of Object.entries(record)) {
    collectInstagramPostImages(
      nested,
      output,
      isMediaNode || mediaKeys.includes(key),
    );
    if (output.length >= maxSocialImages) return;
  }
}

function addInstagramImage(value: unknown, output: string[]) {
  if (typeof value !== "string" || output.length >= maxSocialImages) return;
  const normalized = normalizeEmbeddedJson(value);
  const url = normalized.match(/https:\/\/[^\s"'<>\\]+/)?.[0]
    ?.replace(/[),\]]+$/, "");
  if (url && isAllowedInstagramImage(url) && !hasSameImage(output, url)) {
    output.push(url);
  }
}

function collectInstagramUrlsFromMarkedBlocks(value: string, output: string[]) {
  const markers = [
    "carousel_media",
    "edge_sidecar_to_children",
    "shortcode_media",
    "gql_data",
    "image_versions2",
  ];
  for (const marker of markers) {
    let offset = 0;
    while (output.length < maxSocialImages) {
      const index = value.indexOf(marker, offset);
      if (index < 0) break;
      const block = value.slice(index, Math.min(value.length, index + 250_000));
      for (const match of block.matchAll(/https:\/\/[^\s"'<>\\]+/g)) {
        const url = match[0].replace(/[),\]]+$/, "");
        if (isAllowedInstagramImage(url) && !hasSameImage(output, url)) {
          output.push(url);
        }
        if (output.length >= maxSocialImages) break;
      }
      offset = index + marker.length;
    }
  }
}

/// TikTokが公開HTMLへ埋め込んだ写真カルーセルだけを抽出する。
/// アバターやおすすめ投稿画像が混ざらないよう写真投稿の配下だけを読む。
function extractTikTokPhotoUrls(html: string) {
  const candidates: string[] = [];
  const representative = meta(html, "og:image");
  const scriptPattern = /<script[^>]*>([\s\S]*?)<\/script>/gi;
  for (const match of html.matchAll(scriptPattern)) {
    const raw = match[1]?.trim();
    if (!raw || !looksLikeTikTokPhotoPost(raw)) {
      continue;
    }
    const decoded = normalizeEmbeddedJson(raw);
    try {
      collectPhotoUrls(JSON.parse(decoded), candidates);
    } catch {
      for (const block of decoded.matchAll(/"photoImages"\s*:\s*\[([\s\S]*?)\]\s*[,}]/g)) {
        collectAllowedUrls(block[1] ?? "", candidates);
      }
      for (const block of decoded.matchAll(/"imagePost"\s*:\s*\{([\s\S]*?)\}\s*[,}]/g)) {
        collectAllowedUrls(block[1] ?? "", candidates);
      }
    }
    if (candidates.length >= maxSocialImages) break;
  }
  if (candidates.length === 0 && representative &&
    isAllowedTikTokImage(representative)) {
    candidates.push(representative);
  }
  return [...new Set(candidates)].slice(0, maxSocialImages);
}

function collectPhotoUrls(value: unknown, output: string[]) {
  if (output.length >= maxSocialImages || value == null) return;
  if (Array.isArray(value)) {
    for (const item of value) collectPhotoUrls(item, output);
    return;
  }
  if (typeof value !== "object") return;
  const record = value as Record<string, unknown>;
  // 現行TikTok写真投稿: imagePost.images[].imageURL.urlList[]
  const photoKeys = [
    "imagePost",
    "photoImages",
    "image_post_info",
    "imagePostInfo",
  ];
  for (const key of photoKeys) {
    if (record[key] != null) collectAllowedUrls(record[key], output);
  }
  for (const [key, nested] of Object.entries(record)) {
    if (!photoKeys.includes(key)) {
      collectPhotoUrls(nested, output);
    }
  }
}

function looksLikeTikTokPhotoPost(value: string) {
  return value.includes("imagePost") ||
    value.includes("photoImages") ||
    value.includes("image_post_info") ||
    value.includes("imagePostInfo");
}

function normalizeEmbeddedJson(value: string) {
  return decodeHtml(value)
    .replaceAll("\\u0026", "&")
    .replaceAll("\\u002F", "/")
    .replaceAll("\\/", "/");
}

function collectAllowedUrls(value: unknown, output: string[]) {
  if (output.length >= maxSocialImages || value == null) return;
  if (typeof value === "string") {
    const normalized = decodeHtml(value)
      .replaceAll("\\u002F", "/")
      .replaceAll("\\u0026", "&")
      .replaceAll("\\/", "/");
    for (const match of normalized.matchAll(/https:\/\/[^\s"'<>\\]+/g)) {
      const url = match[0].replace(/[),\]]+$/, "");
      if (isAllowedTikTokImage(url) && !hasSameImage(output, url)) {
        output.push(url);
      }
      if (output.length >= maxSocialImages) return;
    }
    return;
  }
  if (Array.isArray(value)) {
    for (const item of value) collectAllowedUrls(item, output);
    return;
  }
  if (typeof value === "object") {
    const record = value as Record<string, unknown>;
    if (Array.isArray(record.urlList)) {
      for (const candidate of record.urlList) {
        if (typeof candidate !== "string") continue;
        const normalized = normalizeEmbeddedJson(candidate);
        if (isAllowedTikTokImage(normalized) &&
          !hasSameImage(output, normalized)) {
          output.push(normalized);
          break;
        }
      }
    }
    for (const [key, nested] of Object.entries(record)) {
      if (key === "urlList") continue;
      collectAllowedUrls(nested, output);
    }
  }
}

function hasSameImage(output: string[], candidate: string) {
  try {
    const target = new URL(candidate);
    return output.some((value) => {
      try {
        const current = new URL(value);
        return current.hostname === target.hostname &&
          current.pathname === target.pathname;
      } catch {
        return value === candidate;
      }
    });
  } catch {
    return output.includes(candidate);
  }
}

function isAllowedTikTokImage(rawUrl: string) {
  try {
    const url = new URL(rawUrl);
    if (url.protocol !== "https:") return false;
    const host = url.hostname.toLowerCase();
    return ["tiktokcdn.com", "tiktokcdn-us.com", "muscdn.com", "byteimg.com"]
      .some((domain) => host === domain || host.endsWith(`.${domain}`));
  } catch {
    return false;
  }
}

function isAllowedInstagramImage(rawUrl: string) {
  try {
    const url = new URL(rawUrl);
    if (url.protocol !== "https:") return false;
    const host = url.hostname.toLowerCase();
    return ["cdninstagram.com", "fbcdn.net"]
      .some((domain) => host === domain || host.endsWith(`.${domain}`));
  } catch {
    return false;
  }
}

/// 期限付きCDN URLをOpenAIに直接渡すと403や形式判定で全解析が失敗するため、
/// Function側で検証・取得し、安全なdata URLへ変換する。
async function fetchSocialImages(
  urls: string[],
  service: SharedPage["service"] | null,
) {
  const results = await Promise.all(
    urls.slice(0, maxSocialImages).map(async (rawUrl) => {
    const isTikTok = service === "tiktok" && isAllowedTikTokImage(rawUrl);
    const isInstagram = service === "instagram" &&
      isAllowedInstagramImage(rawUrl);
    if (!isTikTok && !isInstagram) return null;
    try {
      const response = await fetch(rawUrl, {
        redirect: "error",
        headers: {
          "Accept": "image/avif,image/webp,image/png,image/jpeg,*/*;q=0.8",
          "User-Agent":
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
          "Referer": isInstagram
            ? "https://www.instagram.com/"
            : "https://www.tiktok.com/",
        },
        signal: AbortSignal.timeout(8000),
      });
      const type = (response.headers.get("content-type") ?? "")
        .split(";")[0]
        .toLowerCase();
      const length = Number(response.headers.get("content-length") ?? "0");
      if (!response.ok ||
        !["image/jpeg", "image/png", "image/webp"].includes(type) ||
        length > 2 * 1024 * 1024) {
        console.warn("social_image_rejected", service, response.status, type, length);
        return null;
      }
      const bytes = new Uint8Array(await response.arrayBuffer());
      if (bytes.length === 0 || bytes.length > 2 * 1024 * 1024) return null;
      return `data:${type};base64,${bytesToBase64(bytes)}`;
    } catch (error) {
      console.warn("social_image_fetch_failed", service, String(error));
      return null;
    }
    }),
  );
  return results.filter((value): value is string => value != null);
}

function bytesToBase64(bytes: Uint8Array) {
  let binary = "";
  const chunkSize = 32 * 1024;
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + chunkSize));
  }
  return btoa(binary);
}

function decodeHtml(value: string) {
  return value
    .replaceAll("&amp;", "&")
    .replaceAll("&quot;", '"')
    .replaceAll("&#39;", "'")
    .replaceAll("&lt;", "<")
    .replaceAll("&gt;", ">");
}

function meta(html: string, key: string) {
  const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const patterns = [
    new RegExp(`<meta[^>]+(?:property|name)=["']${escaped}["'][^>]+content=["']([^"']*)`, "i"),
    new RegExp(`<meta[^>]+content=["']([^"']*)["'][^>]+(?:property|name)=["']${escaped}["']`, "i"),
  ];
  for (const pattern of patterns) {
    const match = html.match(pattern);
    if (match?.[1]) return decodeHtml(match[1].trim()).slice(0, 4000);
  }
  return null;
}

function pageTitle(html: string) {
  const match = html.match(/<title[^>]*>([^<]*)<\/title>/i);
  return match?.[1] ? decodeHtml(match[1].trim()).slice(0, 1000) : null;
}

function reply(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), { status, headers });
}

async function consumeQuota(deviceId: string) {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return false;
  const deviceHash = await hashDeviceId(deviceId);
  const dailyLimit = Math.max(
    1,
    Math.min(200, Number(Deno.env.get("AI_DAILY_DEVICE_LIMIT") ?? "10")),
  );
  const response = await fetch(
    `${supabaseUrl}/rest/v1/rpc/consume_ai_quota`,
    {
      method: "POST",
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        p_device_hash: deviceHash,
        p_limit: dailyLimit,
      }),
      signal: AbortSignal.timeout(5000),
    },
  );
  if (!response.ok) {
    console.error("quota_check_failed", response.status);
    return false;
  }
  return await response.json() === true;
}

async function refundQuota(deviceId: string) {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return;
  const deviceHash = await hashDeviceId(deviceId);
  try {
    const response = await fetch(
      `${supabaseUrl}/rest/v1/rpc/refund_ai_quota`,
      {
        method: "POST",
        headers: {
          apikey: serviceKey,
          Authorization: `Bearer ${serviceKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ p_device_hash: deviceHash }),
        signal: AbortSignal.timeout(5000),
      },
    );
    if (!response.ok) console.error("quota_refund_failed", response.status);
  } catch (error) {
    console.error("quota_refund_failed", String(error));
  }
}

async function hashDeviceId(deviceId: string) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(deviceId),
  );
  return Array.from(new Uint8Array(digest))
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

async function readAnalysisCache(deviceHash: string, analysisKey: string) {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return null;
  try {
    const query = new URL(`${supabaseUrl}/rest/v1/ai_analysis_cache`);
    query.searchParams.set("device_hash", `eq.${deviceHash}`);
    query.searchParams.set("analysis_key", `eq.${analysisKey}`);
    query.searchParams.set("expires_at", `gt.${new Date().toISOString()}`);
    query.searchParams.set("select", "result_json");
    query.searchParams.set("limit", "1");
    const response = await fetch(query, {
      headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}` },
      signal: AbortSignal.timeout(3000),
    });
    if (!response.ok) return null;
    const rows = await response.json();
    return Array.isArray(rows) && rows[0]?.result_json
      ? rows[0].result_json as Record<string, unknown>
      : null;
  } catch (_) {
    return null;
  }
}

async function writeAnalysisCache(
  deviceHash: string,
  analysisKey: string,
  result: Record<string, unknown>,
) {
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceKey) return;
  try {
    await fetch(`${supabaseUrl}/rest/v1/ai_analysis_cache`, {
      method: "POST",
      headers: {
        apikey: serviceKey,
        Authorization: `Bearer ${serviceKey}`,
        "Content-Type": "application/json",
        Prefer: "resolution=merge-duplicates",
      },
      body: JSON.stringify({
        device_hash: deviceHash,
        analysis_key: analysisKey,
        result_json: result,
        expires_at: new Date(Date.now() + 30 * 86400000).toISOString(),
      }),
      signal: AbortSignal.timeout(3000),
    });
  } catch (error) {
    // キャッシュ失敗は解析結果を失敗扱いにしない。
    console.error("analysis_cache_write_failed", String(error));
  }
}
