export type CommentContext = {
  ownerUsername: string;
  ownerId?: string;
  // Only true for Actor runs started by this version with replies disabled.
  parentOnlyRequested?: boolean;
};
function record(value: unknown): Record<string, unknown> | null {
  return value !== null && typeof value === 'object' && !Array.isArray(value)
    ? value as Record<string, unknown> : null;
}
function username(value: unknown): string {
  return String(value ?? '').trim().replace(/^@/, '').normalize('NFKC').toLowerCase();
}
function isParent(row: Record<string, unknown>, context: CommentContext): boolean {
  if (row.isReply === true || row.is_reply === true) return false;
  const fields = ['repliesToId', 'replyToId', 'replyToCommentId', 'inReplyToId',
    'parentCommentId', 'parent_comment_id', 'repliedToCommentId', 'reply_id', 'reply_to_id'];
  let explicit = row.isReply === false || row.is_reply === false;
  for (const field of fields) {
    if (!Object.prototype.hasOwnProperty.call(row, field)) continue;
    explicit = true;
    const value = row[field];
    if (value !== null && value !== undefined && String(value).trim() !== '' &&
        String(value).trim() !== '0') return false;
  }
  // Flat parent rows in Apify's documented output can omit a parent field.
  // Never apply this assumption to older runs that requested replies.
  return explicit || context.parentOnlyRequested === true;
}
export function isRecipeSupplement(text: string): boolean {
  const normalized = text.normalize('NFKC');
  return /材料|分量|作り方|手順|工程|レシピ|訂正|修正|正しくは|誤り|間違|人数|人分|少々|適量|ひとつまみ|お好み|大さじ|小さじ|カップ|ingredients?|recipe|correction|instead|to taste/i.test(normalized) ||
    /\d+(?:[.,/]\d+)?\s*(?:kg|mg|g|ml|cc|l|tbsp|tsp|cups?|servings?|グラム|ミリリットル|リットル|個|本|枚|袋|缶|丁|束|玉|合|人前|人分|分|秒|時間|度|℃)/i.test(normalized) ||
    /半分|半個|半量|倍量|弱火|中火|強火|炒め|煮込|焼[くい]|茹で|ゆで|蒸[すし]|混ぜ|加え|漬け|レンジ|冷蔵|冷凍|沸騰|薄力粉|強力粉|片栗粉|醤油|しょうゆ|みりん|砂糖|塩|胡椒|こしょう|味噌|みそ|バター|牛乳|豆乳|卵|鶏肉|豚肉|牛肉|玉ねぎ|たまねぎ|にんにく|ニンニク/.test(normalized);
}
export function filterRecipeAuthorComments(decoded: unknown, context: CommentContext): string[] {
  const rows = Array.isArray(decoded) ? decoded : [decoded];
  const ownerName = username(context.ownerUsername);
  const ownerId = String(context.ownerId ?? '').trim();
  if (!ownerName && !ownerId) return [];
  const result: string[] = [], seen = new Set<string>();
  for (const value of rows) {
    const row = record(value);
    if (!row || !isParent(row, context)) continue;
    const user = record(row.user) ?? record(row.author) ?? record(row.authorMeta);
    const id = String(user?.uid ?? user?.id ?? row.uid ?? row.userId ?? row.authorId ?? '').trim();
    const name = username(user?.uniqueId ?? user?.unique_id ?? user?.username ??
      row.uniqueId ?? row.username ?? row.authorUsername ?? row.author_name);
    // An available numeric ID is stronger than a matching display/handle name.
    if (ownerId && id ? ownerId !== id : !ownerName || name !== ownerName) continue;
    const text = String(row.text ?? row.comment ?? row.description ?? row.content ?? '')
      .trim().slice(0, 2000);
    if (!text || !isRecipeSupplement(text)) continue;
    const key = text.normalize('NFKC').replace(/\s+/g, ' ');
    if (seen.has(key)) continue;
    seen.add(key); result.push(text);
    if (result.length >= 5) break;
  }
  return result;
}
