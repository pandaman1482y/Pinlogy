import { filterRecipeAuthorComments as filter, isRecipeSupplement } from '../_shared/recipe-author-comments.ts';
function assert(value: boolean) { if (!value) throw new Error('assertion failed'); }
const context={ownerUsername:'cook',ownerId:'123',parentOnlyRequested:true};
const row=(text:string,extra:Record<string,unknown>={})=>({text,uniqueId:'cook',uid:'123',...extra});
Deno.test('投稿主の分量・適量・訂正・短い材料コメントを残す',()=>{
  for(const text of ['しょうゆ 大さじ2','豆腐150g','塩少々','2人分です','半分にしてください','訂正:水は100ml','薄力粉です']) assert(filter([row(text)],context).length===1);
});
Deno.test('他人と返信を除外し、返信数のある親コメントは残す',()=>{
  assert(filter([row('砂糖20g',{uid:'999'}),row('砂糖20g',{repliesToId:'777'}),row('砂糖20g',{isReply:true})],context).length===0);
  assert(filter([row('砂糖20g',{replyCommentTotal:3,repliesToId:'0'})],context).length===1);
});
Deno.test('旧ジョブで判定情報がないコメントを親と断定しない',()=>{
  assert(filter([row('塩1g')],{...context,parentOnlyRequested:false}).length===0);
  assert(filter([row('塩1g',{reply_id:0})],{...context,parentOnlyRequested:false}).length===1);
});
Deno.test('雑談・数字だけの反応を落とし、重複を除外する',()=>{
  assert(filter([row('ありがとうございます'),row('100回見た！'),row('砂糖20g'),row('砂糖２０g')],context).length===1);
});
Deno.test('IDが取得できない場合は固有ユーザー名で照合する',()=>{
  assert(filter([{uniqueId:'@Cook',text:'油適量'}],context).length===1);
  assert(filter([{user:{name:'cook'},text:'油適量'}],context).length===0);
});
Deno.test('取得上限・文量上限と元の改行を維持する',()=>{
  const result=filter(Array.from({length:10},(_,i)=>row(`材料\n水${i+1}ml`)),context);
  assert(result.length===5);assert(result[0].includes('\n'));
  assert(isRecipeSupplement('flour 100 g'));assert(isRecipeSupplement('2 servings'));
});
