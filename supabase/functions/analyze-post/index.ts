import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const headers = { "Content-Type": "application/json; charset=utf-8" };

Deno.serve(async (request) => {
  if (request.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
  const apiKey = Deno.env.get("OPENAI_API_KEY");
  if (!apiKey) return reply({ error: "ai_not_configured" }, 503);

  const deviceId = request.headers.get("x-pinlogy-device") ?? "";
  if (!/^[0-9a-f-]{32,40}$/i.test(deviceId)) {
    return reply({ error: "device_id_required" }, 400);
  }
  if (!await consumeQuota(deviceId)) {
    return reply({ error: "daily_limit_reached" }, 429);
  }

  try {
    const input = await request.json();
    const sourcePostId = String(input.source_post_id ?? "");
    if (!sourcePostId) return reply({ error: "invalid_request" }, 400);
    const sharedPage = await enrichSharedUrl(
      typeof input.url === "string" ? input.url : "",
    );

    const content: Array<Record<string, unknown>> = [{
      type: "input_text",
      text: [
        `投稿文:\n${String(input.text ?? "")}`,
        `端末OCR:\n${String(input.ocr_text ?? "")}`,
        `共有URL:\n${String(input.url ?? "")}`,
        `URLから取得した投稿情報:\n${JSON.stringify(
          sharedPage == null ? {} : { ...sharedPage, image_urls: undefined },
        )}`,
        `端末候補:\n${JSON.stringify(input.local_candidates ?? [])}`,
      ].join("\n\n"),
    }];
    const suppliedImages = validImages(input.image_data_urls);
    for (const image of suppliedImages) {
      content.push({ type: "input_image", image_url: image, detail: "high" });
    }
    // TikTok写真投稿は共有拡張へ画像本体を渡さないことがある。
    // 公開ページ内に掲載された写真URLだけを同じ1回の解析へ追加する。
    for (const image of (sharedPage?.image_urls ?? []).slice(
      0,
      Math.max(0, 5 - suppliedImages.length),
    )) {
      content.push({ type: "input_image", image_url: image, detail: "high" });
    }

    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: { Authorization: `Bearer ${apiKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: Deno.env.get("OPENAI_MODEL") ?? "gpt-5.6-luna",
        store: false,
        reasoning: { effort: "low" },
        max_output_tokens: 2500,
        tools: [{ type: "web_search" }],
        instructions:
          "日本国内の店舗・観光地を投稿文、端末OCR、共有画像、共有URL情報から抽出してください。店名または住所が書かれている場合は、端末候補が空でも必ずWeb検索し、実在性と正式住所を確認して候補化してください。画像内の手書き・装飾文字も読み取り対象です。同名店は地域・住所の根拠が一致するまで断定しないでください。特定できた候補は、店舗入口または建物中心のlatitudeとlongitudeをWeb上の公式情報で確認して返してください。categoryは飲食店、観光・レジャー、宿泊、買い物、その他のいずれか、genresは具体的な種類を最大3件とします。住所や座標が不明・矛盾・推測ならneedsReviewまたはunresolvedとし、latitudeとlongitudeはnullにしてください。1投稿に複数場所があれば別候補にし、保存理由は投稿中の表現だけから42文字以内で要約してください。候補が0件でURLから取得した投稿情報のis_photo_postがtrueかつphoto_accessがunavailableの場合、raw_summaryは「TikTokの画像を取得できませんでした。店名などが写ったスクリーンショットを追加してください。」としてください。",
        input: [{ role: "user", content }],
        text: { verbosity: "low", format: placeSchema },
      }),
    });
    if (!response.ok) {
      const detail = (await response.text()).slice(0, 1000);
      console.error("openai_failed", response.status, detail);
      return reply({ error: "openai_failed" }, 502);
    }
    const value = await response.json();
    const output = value.output
      ?.flatMap((item: { content?: unknown[] }) => item.content ?? [])
      .find((part: { type?: string }) => part.type === "output_text") as
      | { text?: string }
      | undefined;
    if (!output?.text) return reply({ error: "empty_ai_response" }, 502);
    return reply({
      source_post_id: sourcePostId,
      ...JSON.parse(output.text),
      analysis_source: sharedPage?.is_photo_post === true
        ? (sharedPage.image_urls.length > 0
          ? "ai_tiktok_photos"
          : "ai_tiktok_text_only")
        : "ai",
      shared_media: sharedPage == null
        ? null
        : {
          is_photo_post: sharedPage.is_photo_post,
          photo_access: sharedPage.photo_access,
          image_count: sharedPage.image_urls.length,
        },
    });
  } catch (error) {
    console.error("analysis_failed", error);
    return reply({ error: "analysis_failed" }, 500);
  }
});

const placeSchema = {
  type: "json_schema",
  name: "pinlogy_places",
  strict: true,
  schema: {
    type: "object",
    additionalProperties: false,
    required: ["raw_summary", "candidates"],
    properties: {
      raw_summary: { type: "string" },
      candidates: {
        type: "array",
        maxItems: 10,
        items: {
          type: "object",
          additionalProperties: false,
          required: ["name", "address", "reason", "category", "genres", "evidenceSummary", "confidencePercent", "match", "postAddress", "latitude", "longitude"],
          properties: {
            name: { type: "string" },
            address: { type: ["string", "null"] },
            reason: { type: ["string", "null"] },
            category: { type: "string", enum: ["飲食店", "観光・レジャー", "宿泊", "買い物", "その他"] },
            genres: { type: "array", maxItems: 3, items: { type: "string" } },
            evidenceSummary: { type: ["string", "null"] },
            confidencePercent: { type: "integer", minimum: 0, maximum: 100 },
            match: { type: "string", enum: ["high", "needsReview", "unresolved"] },
            postAddress: { type: ["string", "null"] },
            latitude: { type: ["number", "null"], minimum: -90, maximum: 90 },
            longitude: { type: ["number", "null"], minimum: -180, maximum: 180 },
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
    .slice(0, 5);
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
  canonical_url: string;
  title: string | null;
  description: string | null;
  oembed?: Record<string, unknown>;
  is_photo_post: boolean;
  photo_access: "available" | "unavailable" | "not_applicable";
  image_urls: string[];
  fetch_status: number;
};

async function enrichSharedUrl(rawUrl: string): Promise<SharedPage | null> {
  if (!rawUrl) return null;
  try {
    const initial = new URL(rawUrl);
    if (!isAllowedSocialUrl(initial)) return null;
    const { response, finalUrl } = await fetchSocialPage(initial);
    const final = new URL(finalUrl);
    const isTikTok = final.hostname.toLowerCase().endsWith("tiktok.com");
    const isPhotoPost = isTikTok && /\/photo\/\d+/.test(final.pathname);
    if (!response.ok) {
      console.warn("shared_page_http_failed", response.status, final.hostname);
      return {
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
    const imageUrls = isPhotoPost ? extractTikTokPhotoUrls(html) : [];
    const metadata: SharedPage = {
      canonical_url: finalUrl,
      title: meta(html, "og:title") ?? pageTitle(html),
      description: meta(html, "og:description") ?? meta(html, "description"),
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

/// TikTokが公開HTMLへ埋め込んだ写真カルーセルだけを抽出する。
/// アバターやおすすめ投稿画像が混ざらないよう写真投稿の配下だけを読む。
function extractTikTokPhotoUrls(html: string) {
  const candidates: string[] = [];
  const scriptPattern = /<script[^>]*>([\s\S]*?)<\/script>/gi;
  for (const match of html.matchAll(scriptPattern)) {
    const raw = match[1]?.trim();
    if (!raw || (!raw.includes("imagePost") && !raw.includes("photoImages"))) {
      continue;
    }
    const decoded = decodeHtml(raw);
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
    if (candidates.length >= 5) break;
  }
  return [...new Set(candidates)].slice(0, 5);
}

function collectPhotoUrls(value: unknown, output: string[]) {
  if (output.length >= 5 || value == null) return;
  if (Array.isArray(value)) {
    for (const item of value) collectPhotoUrls(item, output);
    return;
  }
  if (typeof value !== "object") return;
  const record = value as Record<string, unknown>;
  // 現行TikTok写真投稿: imagePost.images[].imageURL.urlList[]
  const imagePost = record.imagePost;
  if (imagePost != null) collectAllowedUrls(imagePost, output);
  const photos = record.photoImages;
  if (Array.isArray(photos)) {
    for (const photo of photos) collectAllowedUrls(photo, output);
  }
  for (const [key, nested] of Object.entries(record)) {
    if (key !== "imagePost" && key !== "photoImages") {
      collectPhotoUrls(nested, output);
    }
  }
}

function collectAllowedUrls(value: unknown, output: string[]) {
  if (output.length >= 5 || value == null) return;
  if (typeof value === "string") {
    const normalized = decodeHtml(value)
      .replaceAll("\\u002F", "/")
      .replaceAll("\\u0026", "&")
      .replaceAll("\\/", "/");
    for (const match of normalized.matchAll(/https:\/\/[^\s"'<>\\]+/g)) {
      const url = match[0].replace(/[),\]]+$/, "");
      if (isAllowedTikTokImage(url) && !output.includes(url)) output.push(url);
      if (output.length >= 5) return;
    }
    return;
  }
  if (Array.isArray(value)) {
    for (const item of value) collectAllowedUrls(item, output);
    return;
  }
  if (typeof value === "object") {
    for (const nested of Object.values(value as Record<string, unknown>)) {
      collectAllowedUrls(nested, output);
    }
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
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(deviceId),
  );
  const deviceHash = Array.from(new Uint8Array(digest))
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
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
