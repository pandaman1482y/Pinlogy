import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const headers = { "Content-Type": "application/json; charset=utf-8" };

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return reply({ error: "method_not_allowed" }, 405);
  }
  let deviceId = "";
  let quotaReserved = false;
  try {
    const apiKey = Deno.env.get("OPENAI_API_KEY")?.trim();
    if (!apiKey) return reply({ error: "ai_not_configured" }, 503);
    deviceId = request.headers.get("x-pinlogy-device") ?? "";
    if (!/^[0-9a-f-]{32,40}$/i.test(deviceId)) {
      return reply({ error: "device_id_required" }, 400);
    }
    if (!await consumeQuota(deviceId)) {
      return reply({ error: "daily_limit_reached" }, 429);
    }
    quotaReserved = true;
    const input = await request.json();
    const query = String(input.query ?? "").trim().slice(0, 1000);
    if (!query) return reply({ error: "query_required" }, 400);
    const recipes = Array.isArray(input.recipes) ? input.recipes.slice(0, 100) : [];
    const allergens = stringArray(input.allergens).slice(0, 30);
    const dislikedFoods = stringArray(input.disliked_foods).slice(0, 30);

    const response = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: Deno.env.get("OPENAI_MODEL") ?? "gpt-5.6-luna",
        store: false,
        reasoning: { effort: "low" },
        max_output_tokens: 900,
        instructions:
          "あなたは保存済みレシピを探す日本語の料理アシスタントです。" +
          "saved_recipe_idsには入力されたrecipes内の実在するidだけを、適合度順に最大5件返してください。" +
          "保存数が少ない、または一致が弱い場合はnew_suggestionsへ短い料理案を最大3件返します。" +
          "保存済みと新しい提案は混同しないでください。ユーザーが『最近』と言えばlast_made_atとmade_countを考慮します。" +
          "allergensに一致または含有の可能性がある保存レシピは推薦から除外してください。" +
          "抽出漏れや交差接触があり得るため安全を保証せず、アレルギー設定がある場合warningへ確認文を必ず返してください。",
        input: [{
          role: "user",
          content: [{
            type: "input_text",
            text: JSON.stringify({ query, recipes, allergens, disliked_foods: dislikedFoods }),
          }],
        }],
        text: {
          verbosity: "low",
          format: {
            type: "json_schema",
            name: "recipe_assistant_answer",
            strict: true,
            schema: {
              type: "object",
              additionalProperties: false,
              required: ["message", "saved_recipe_ids", "new_suggestions", "warning"],
              properties: {
                message: { type: "string" },
                saved_recipe_ids: { type: "array", items: { type: "string" } },
                new_suggestions: { type: "array", items: { type: "string" } },
                warning: { type: ["string", "null"] },
              },
            },
          },
        },
      }),
      signal: AbortSignal.timeout(30_000),
    });
    if (!response.ok) {
      console.warn("recipe_assistant_failed", response.status);
      await refundQuota(deviceId);
      quotaReserved = false;
      return reply({ error: "ai_failed" }, 502);
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
    const result = JSON.parse(output.text);
    const allowedIds = new Set(
      recipes
        .map((recipe: Record<string, unknown>) => String(recipe?.id ?? ""))
        .filter(Boolean),
    );
    result.saved_recipe_ids = stringArray(result.saved_recipe_ids)
      .filter((id) => allowedIds.has(id))
      .slice(0, 5);
    result.new_suggestions = stringArray(result.new_suggestions).slice(0, 3);
    quotaReserved = false;
    return reply(result);
  } catch (error) {
    if (quotaReserved && deviceId) await refundQuota(deviceId);
    console.error("recipe_assistant_error", String(error));
    return reply({ error: "invalid_request" }, 400);
  }
});

function stringArray(value: unknown) {
  return Array.isArray(value)
    ? value.map((item) => String(item).trim()).filter(Boolean)
    : [];
}

function reply(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers });
}

async function deviceHash(deviceId: string) {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(deviceId),
  );
  return Array.from(new Uint8Array(digest))
    .map((value) => value.toString(16).padStart(2, "0"))
    .join("");
}

async function quotaRpc(name: "consume_ai_quota" | "refund_ai_quota", deviceId: string) {
  const url = Deno.env.get("SUPABASE_URL")?.trim();
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  if (!url || !key) return name === "consume_ai_quota";
  const response = await fetch(`${url.replace(/\/$/, "")}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${key}`,
      "apikey": key,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ p_device_hash: await deviceHash(deviceId) }),
    signal: AbortSignal.timeout(5000),
  });
  if (!response.ok) return false;
  return name === "consume_ai_quota" ? await response.json() === true : true;
}

async function consumeQuota(deviceId: string) {
  try {
    return await quotaRpc("consume_ai_quota", deviceId);
  } catch (_) {
    return false;
  }
}

async function refundQuota(deviceId: string) {
  try {
    await quotaRpc("refund_ai_quota", deviceId);
  } catch (_) {
    // A refund failure must not hide the original service error.
  }
}
