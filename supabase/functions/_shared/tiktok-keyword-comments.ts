import { filterRecipeAuthorComments } from './recipe-author-comments.ts';

export const recipeCommentKeywords = [
  '材料', '分量', 'レシピ', '作り方', '大さじ', '小さじ', '人分', '人前',
  '適量', '少々', 'グラム', 'ml', 'g', '個', '砂糖', '醤油', 'しょうゆ',
  'みりん', '片栗粉', '塩', '鶏', 'じゃが', '訂正',
];
export function keywordCommentInput(url: string) {
  return {
    videos: [url], keywords: recipeCommentKeywords, maxComments: 40,
    includeReplies: false, maxRepliesPerComment: 0, maxVideosPerProfile: 1,
    analyzeSentiment: false, findLeads: false, onlyNew: false, maxConcurrency: 1,
  };
}
export type KeywordPost = {
  ownerUsername: string; ownerId?: string; authorComments: string[];
};
type Dependencies = {
  fetch: (url: string, init?: RequestInit) => Promise<Response>;
  requeue: (request: Record<string, unknown>) => Promise<void>;
  enabled: boolean;
  now?: () => number;
  log: (event: string, fields: Record<string, unknown>) => void;
};
// Persist the Actor run across Edge Function invocations. Polls never start another run.
export async function prepareKeywordComments(
  request: Record<string, unknown>, post: KeywordPost, deps: Dependencies,
): Promise<Record<string, unknown> | null> {
  const now = deps.now ?? Date.now;
  const finish = (reason: string) => {
    delete request.__tiktok_keyword_comments;
    request.__tiktok_keyword_comments_done = true;
    deps.log('async_tiktok_keyword_comments_finished', { reason, accepted: post.authorComments.length });
    return request;
  };
  if (!deps.enabled) return finish('disabled');
  if (request.__tiktok_keyword_comments_done === true) return request;
  if (!post.ownerUsername && !post.ownerId) return finish('owner_missing');
  let state = request.__tiktok_keyword_comments as Record<string, unknown> | undefined;
  const videoId = /\/(?:video|photo)\/(\d{8,30})/.exec(String(request.__tiktok_canonical_url ?? request.url ?? ''))?.[1];
  if (!videoId) return finish('video_id_missing');
  if (!state) {
    const kind = String(request.__tiktok_canonical_url ?? request.url ?? '').includes('/photo/') ? 'photo' : 'video';
    const url = `https://www.tiktok.com/@_/${kind}/${videoId}`;
    try {
      const response = await deps.fetch(
        'https://api.apify.com/v2/acts/s_actors~tiktok-comments-scraper/runs?timeout=120&maxTotalChargeUsd=0.02',
        { method: 'POST', headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(keywordCommentInput(url)), signal: AbortSignal.timeout(20_000) },
      );
      if (!response.ok) return finish(`start_http_${response.status}`);
      const data = (await response.json()).data;
      const runId = String(data?.id ?? '');
      if (!/^[a-zA-Z0-9]{17}$/.test(runId)) return finish('invalid_run_id');
      state = { run_id: runId, started_at: now(), attempt: 0 };
      request.__tiktok_keyword_comments = state;
      deps.log('async_tiktok_keyword_comments_started', { run_id: runId, max_results: 40 });
    } catch {
      // A timed-out POST may have started remotely; never blindly retry a paid run.
      return finish('start_failed');
    }
    await deps.requeue(request);
    return null;
  }
  const runId = String(state.run_id ?? '');
  if (!/^[a-zA-Z0-9]{17}$/.test(runId)) return finish('invalid_state');
  const startedAt = Number(state.started_at);
  const attempt = Number(state.attempt);
  if (!Number.isFinite(startedAt) || !Number.isInteger(attempt) || attempt < 0) return finish('invalid_state');
  if (now() - startedAt > 150_000 || attempt >= 30) {
    try { await deps.fetch(`https://api.apify.com/v2/actor-runs/${runId}/abort`,
      { method: 'POST', signal: AbortSignal.timeout(5_000) }); } catch { /* Actor also has its own timeout. */ }
    return finish('timeout');
  }
  try {
    const response = await deps.fetch(`https://api.apify.com/v2/actor-runs/${runId}`,
      { signal: AbortSignal.timeout(12_000) });
    if (!response.ok) throw new Error('progress_failed');
    const data = (await response.json()).data;
    const status = String(data?.status ?? '').toUpperCase();
    if (['SUCCEEDED', 'TIMED-OUT', 'ABORTED'].includes(status)) {
      const datasetId = String(data?.defaultDatasetId ?? '');
      if (!/^[a-zA-Z0-9]{17}$/.test(datasetId)) return finish('dataset_missing');
      const dataset = await deps.fetch(`https://api.apify.com/v2/datasets/${datasetId}/items?clean=true&format=json&limit=40`,
        { signal: AbortSignal.timeout(20_000) });
      if (!dataset.ok) throw new Error('dataset_failed');
      const rows = await dataset.json();
      if (!Array.isArray(rows)) return finish('dataset_invalid');
      // Never trust creator badges, display names or likes as proof of authorship.
      const matchingPost = rows.filter(row => row && String(row.videoId ?? '') === videoId);
      const accepted = filterRecipeAuthorComments(matchingPost, {
        ownerUsername: post.ownerUsername, ownerId: post.ownerId, parentOnlyRequested: true,
      });
      post.authorComments = [...new Set([...post.authorComments, ...accepted])].slice(0, 5);
      request.tiktok_external_post = post;
      deps.log('async_tiktok_keyword_comments_filtered', {
        run_id: runId, rows: rows.length, matching_post: matchingPost.length,
        accepted: accepted.length, status, charge_usd: data?.usageTotalUsd ?? null,
      });
      return finish(status.toLowerCase());
    }
    if (status === 'FAILED') return finish('actor_failed');
  } catch {
    deps.log('async_tiktok_keyword_comments_poll_failed', { run_id: runId, attempt });
  }
  state.attempt = attempt + 1;
  await deps.requeue(request);
  return null;
}
