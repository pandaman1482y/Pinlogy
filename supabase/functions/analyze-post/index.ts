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
      text: JSON.stringify({
        ...input,
        image_data_urls: undefined,
        shared_page: sharedPage,
      }),
    }];
    for (const image of validImages(input.image_data_urls)) {
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
          "日本国内の店舗・観光地を投稿文、端末OCR、共有画像、共有URL、shared_pageから抽出してください。Web検索で実在性と正式住所を確認し、同名店は地域・住所の根拠が一致するまで断定しないでください。特定できた候補は地図でピン表示できるよう、店舗入口または建物中心の緯度latitudeと経度longitudeをWeb上の地図・公式情報で確認して数値で返してください。categoryは飲食店、観光・レジャー、宿泊、買い物、その他のいずれかにし、genresは料理や施設の具体的な種類（例：ラーメン、カフェ、焼肉、神社）を最大3件返してください。住所や座標が不明・矛盾・推測の場合はneedsReviewまたはunresolvedとし、latitudeとlongitudeはnullにしてください。1投稿に複数場所があれば別候補にします。保存理由は投稿中の表現だけから42文字以内で要約してください。",
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
    return reply({ source_post_id: sourcePostId, ...JSON.parse(output.text) });
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
    .slice(0, 3);
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

async function enrichSharedUrl(rawUrl: string) {
  if (!rawUrl) return null;
  try {
    const initial = new URL(rawUrl);
    if (!isAllowedSocialUrl(initial)) return null;
    const { response, finalUrl } = await fetchSocialPage(initial);
    const html = (await response.text()).slice(0, 750_000);
    const metadata: Record<string, unknown> = {
      canonical_url: finalUrl,
      title: meta(html, "og:title") ?? pageTitle(html),
      description: meta(html, "og:description") ?? meta(html, "description"),
    };

    if (new URL(finalUrl).hostname.toLowerCase().endsWith("tiktok.com")) {
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
