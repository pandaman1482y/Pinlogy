import { prepareKeywordComments, keywordCommentInput } from '../_shared/tiktok-keyword-comments.ts';
import { filterRecipeAuthorComments } from '../_shared/recipe-author-comments.ts';
function assert(value: unknown) { if (!value) throw new Error('assertion failed'); }
const videoId='7646728112784362772', run='abcdefghijklmnopq', dataset='ABCDEFGHIJKLMNOPQ';
const post=()=>({ownerUsername:'namigohan_',ownerId:'123',authorComments:[] as string[]});
const request=()=>({url:'https://lite.tiktok.com/t/ZSbw7p29E/',__tiktok_canonical_url:`https://www.tiktok.com/@_/${'video'}/${videoId}`} as Record<string,unknown>);
const response=(data:unknown)=>new Response(JSON.stringify({data}));
Deno.test('keyword input excludes replies and paid enrichment with a finite result cap',()=>{
 const input=keywordCommentInput('url');assert(input.maxComments===40);assert(!input.includeReplies);assert(!input.findLeads);assert(!input.analyzeSentiment);assert(input.keywords.includes('大さじ'));
});
Deno.test('flat output uses real author IDs; likes and display names never prove identity',()=>{
 const rows=[{text:'砂糖20g',authorId:'999',authorUsername:'namigohan_',isReply:false},
 {text:'材料\nしょうゆ大さじ2',authorId:'123',authorUsername:'namigohan_',isReply:false},
 {text:'水100ml',authorId:'123',isReply:true},
 {text:'卵2個',authorId:'123',repliedToCommentId:'777'}];
 const accepted=filterRecipeAuthorComments(rows,{ownerUsername:'namigohan_',ownerId:'123',parentOnlyRequested:true});
 assert(accepted.length===1);assert(accepted[0].includes('\n'));
});
Deno.test('start once, resume with run ID, exclude other users and videos before AI',async()=>{
 const req=request(), external=post(); let starts=0, queues=0;
 const deps={enabled:true,now:()=>1000,log:()=>{},requeue:async()=>{queues++},fetch:async(url:string,init?:RequestInit)=>{
 if(url.includes('/acts/')){starts++;assert(JSON.parse(String(init?.body)).videos[0].includes(videoId));return response({id:run})}
 if(url.includes('/actor-runs/'))return response({status:'SUCCEEDED',defaultDatasetId:dataset,usageTotalUsd:0.001});
 return new Response(JSON.stringify([
 {videoId,authorId:'123',authorUsername:'namigohan_',text:'砂糖20g',isReply:false},
 {videoId,authorId:'999',text:'塩1g',isReply:false},
 {videoId:'9999999999',authorId:'123',text:'水100ml',isReply:false},
 ]));}};
 assert(await prepareKeywordComments(req,external,deps)===null);assert(starts===1&&queues===1);
 assert(await prepareKeywordComments(req,external,deps)===req);assert(external.authorComments.length===1);assert(req.__tiktok_keyword_comments_done===true);
 await prepareKeywordComments(req,external,deps);assert(starts===1);
});
Deno.test('running polls preserve state without repeating the paid POST',async()=>{
 const req=request();req.__tiktok_keyword_comments={run_id:run,started_at:1000,attempt:0};let calls=0;
 const out=await prepareKeywordComments(req,post(),{enabled:true,now:()=>2000,log:()=>{},requeue:async()=>{},fetch:async(url)=>{calls++;assert(!url.includes('/acts/'));return response({status:'RUNNING'})}});
 assert(out===null&&calls===1);assert((req.__tiktok_keyword_comments as {attempt:number}).attempt===1);
});
Deno.test('timeout aborts once and continues; failed start is not retried',async()=>{
 const req=request();req.__tiktok_keyword_comments={run_id:run,started_at:1000,attempt:0};let aborted=false;
 assert(await prepareKeywordComments(req,post(),{enabled:true,now:()=>200000,log:()=>{},requeue:async()=>{throw Error('unexpected queue')},fetch:async(url)=>{aborted=url.endsWith('/abort');return response({})}})===req);assert(aborted);
 const bad=request();let attempts=0;const deps={enabled:true,log:()=>{},requeue:async()=>{},fetch:async()=>{attempts++;throw Error('network')}};
 await prepareKeywordComments(bad,post(),deps);await prepareKeywordComments(bad,post(),deps);assert(attempts===1);
});
Deno.test('disabled mode never calls the paid service',async()=>{
 const req=request();assert(await prepareKeywordComments(req,post(),{enabled:false,log:()=>{},requeue:async()=>{},fetch:async()=>{throw Error('unexpected request')}})===req);
});
