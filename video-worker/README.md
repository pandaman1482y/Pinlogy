# Pinlogy video worker

TikTok / Instagram の公開動画を一時取得し、レシピ解析用の静止画と音声文字起こしを返す Cloud Run ワーカーです。

TikTokはBright Data Posts Scraperが返す署名付き`video_url`を受け取り、
TikTokページへ直接アクセスせずに動画本体を処理します。ISPプロキシ経由の
TikTok直接アクセスはBright Dataのサポート対象外なので使用しません。

- 動画は処理中の一時ディレクトリだけに保存し、レスポンス後に削除します。
- 対象は最大 3 分、80 MB です。
- 2 fps で読み取り、場面変化と一定間隔から最大 20 枚を選びます。
- `VIDEO_WORKER_SECRET` による Bearer 認証が必須です。
- 非公開投稿、ログイン必須投稿、配信側が取得を拒否する投稿は処理できません。

## Cloud Run への配備

Google Cloud CLI にログインし、リポジトリのルートで実行します。

```bash
gcloud auth login
gcloud config set project pinlogy-a59f3
gcloud services enable run.googleapis.com cloudbuild.googleapis.com secretmanager.googleapis.com

read -s -p "OpenAI API key: " OPENAI_API_KEY; echo
VIDEO_WORKER_SECRET="$(openssl rand -hex 32)"

printf %s "$OPENAI_API_KEY" | \
  gcloud secrets create pinlogy-openai-key --data-file=- 2>/dev/null || \
printf %s "$OPENAI_API_KEY" | \
  gcloud secrets versions add pinlogy-openai-key --data-file=-

printf %s "$VIDEO_WORKER_SECRET" | \
  gcloud secrets create pinlogy-video-worker-secret --data-file=- 2>/dev/null || \
printf %s "$VIDEO_WORKER_SECRET" | \
  gcloud secrets versions add pinlogy-video-worker-secret --data-file=-

gcloud run deploy pinlogy-video-worker \
  --source video-worker \
  --region asia-northeast1 \
  --allow-unauthenticated \
  --cpu 2 \
  --memory 2Gi \
  --timeout 300 \
  --concurrency 2 \
  --max-instances 3 \
  --set-secrets OPENAI_API_KEY=pinlogy-openai-key:latest,VIDEO_WORKER_SECRET=pinlogy-video-worker-secret:latest

VIDEO_WORKER_URL="$(gcloud run services describe pinlogy-video-worker \
  --region asia-northeast1 --format='value(status.url)')"

npx supabase@latest secrets set \
  VIDEO_WORKER_URL="$VIDEO_WORKER_URL" \
  VIDEO_WORKER_SECRET="$VIDEO_WORKER_SECRET"

npx supabase@latest functions deploy analyze-post
npx supabase@latest functions deploy enqueue-analysis

unset OPENAI_API_KEY VIDEO_WORKER_SECRET VIDEO_WORKER_URL
```

Cloud Run 自体は公開 URL にしますが、`/extract` は共有シークレットが一致しない要求を拒否します。

## 動作確認

Cloud Run のヘルスチェック:

```bash
VIDEO_WORKER_URL="$(gcloud run services describe pinlogy-video-worker \
  --region asia-northeast1 --format='value(status.url)')"
curl -sS "$VIDEO_WORKER_URL/health"
```

アプリから公開動画を共有した後、Supabase の `analyze-post` ログで次を確認します。

```text
video_worker_resolved frames=... transcript=...
```

続いて `enqueue-analysis` ログに次が出れば、保存と通知送信まで完了しています。

```text
async_job_completed ... returned_images=...
fcm_send_succeeded ...
```

Instagram がログインを要求する場合は、Netscape 形式の Cookie ファイルを Base64 化した `YTDLP_COOKIES_B64` を Cloud Run の Secret として追加できます。Cookie は専用テストアカウントのものを使い、定期的に更新してください。
