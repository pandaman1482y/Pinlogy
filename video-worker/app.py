import base64
import hmac
import io
import os
import subprocess
import tempfile
from pathlib import Path
from urllib.parse import urlparse

from fastapi import FastAPI, Header, HTTPException
from openai import OpenAI
from PIL import Image, ImageChops, ImageStat
from pydantic import BaseModel
from yt_dlp import YoutubeDL

app = FastAPI()
MAX_VIDEO_BYTES = 80 * 1024 * 1024
MAX_DURATION_SECONDS = 180
MAX_FRAMES = 20
FRAME_RATE = 2


class ExtractRequest(BaseModel):
    url: str


def _allowed_url(raw: str) -> bool:
    try:
        parsed = urlparse(raw)
        host = (parsed.hostname or "").lower()
        return parsed.scheme == "https" and (
            host == "tiktok.com"
            or host.endswith(".tiktok.com")
            or host == "instagram.com"
            or host.endswith(".instagram.com")
        )
    except ValueError:
        return False


def _run(command: list[str]) -> str:
    completed = subprocess.run(
        command,
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=240,
    )
    return completed.stdout.strip()


def _difference(left: Image.Image, right: Image.Image) -> float:
    difference = ImageChops.difference(left.convert("RGB"), right.convert("RGB"))
    values = ImageStat.Stat(difference).rms
    return sum(values) / len(values)


def _select_frames(frame_paths: list[Path]) -> list[tuple[Path, float]]:
    if not frame_paths:
        return []
    selected: list[tuple[Path, float]] = []
    previous: Image.Image | None = None
    last_selected_second = -99.0
    for index, path in enumerate(frame_paths):
        second = index / FRAME_RATE
        with Image.open(path) as opened:
            current = opened.convert("RGB").resize((192, 108))
            changed = previous is None or _difference(previous, current) >= 7.0
            periodic = second - last_selected_second >= 4.0
            if changed or periodic:
                selected.append((path, second))
                last_selected_second = second
            previous = current.copy()
    if len(selected) <= MAX_FRAMES:
        return selected
    indexes = {
        round(index * (len(selected) - 1) / (MAX_FRAMES - 1))
        for index in range(MAX_FRAMES)
    }
    return [selected[index] for index in sorted(indexes)]


def _encode_frame(path: Path, second: float) -> dict:
    with Image.open(path) as image:
        image = image.convert("RGB")
        buffer = io.BytesIO()
        image.save(buffer, format="JPEG", quality=72, optimize=True)
    encoded = base64.b64encode(buffer.getvalue()).decode("ascii")
    return {
        "timestamp_seconds": round(second),
        "data_url": f"data:image/jpeg;base64,{encoded}",
    }


def _transcribe(audio_path: Path) -> str:
    api_key = os.getenv("OPENAI_API_KEY", "").strip()
    if not api_key or not audio_path.exists() or audio_path.stat().st_size == 0:
        return ""
    try:
        client = OpenAI(api_key=api_key, timeout=120)
        with audio_path.open("rb") as audio:
            result = client.audio.transcriptions.create(
                model=os.getenv("OPENAI_TRANSCRIBE_MODEL", "gpt-4o-mini-transcribe"),
                file=audio,
                language="ja",
            )
        return (result.text or "").strip()[:12000]
    except Exception as error:
        print(f"transcription_failed {type(error).__name__}", flush=True)
        return ""


@app.get("/health")
def health() -> dict:
    return {"ok": True}


@app.post("/extract")
def extract(
    request: ExtractRequest,
    authorization: str | None = Header(default=None),
) -> dict:
    secret = os.getenv("VIDEO_WORKER_SECRET", "").strip()
    supplied = (authorization or "").removeprefix("Bearer ").strip()
    if not secret or not hmac.compare_digest(secret, supplied):
        raise HTTPException(status_code=401, detail="unauthorized")
    if not _allowed_url(request.url):
        raise HTTPException(status_code=400, detail="unsupported_url")

    with tempfile.TemporaryDirectory() as temporary:
        root = Path(temporary)
        output_template = str(root / "source.%(ext)s")
        options = {
            "format": "best[height<=720]/best",
            "outtmpl": output_template,
            "noplaylist": True,
            "quiet": True,
            "no_warnings": True,
            "max_filesize": MAX_VIDEO_BYTES,
            "socket_timeout": 20,
            "retries": 2,
            "http_headers": {
                "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148"
            },
        }
        cookies_b64 = os.getenv("YTDLP_COOKIES_B64", "").strip()
        if cookies_b64:
            try:
                cookies_path = root / "cookies.txt"
                cookies_path.write_bytes(base64.b64decode(cookies_b64, validate=True))
                options["cookiefile"] = str(cookies_path)
            except Exception:
                print("video_cookies_invalid", flush=True)
        try:
            with YoutubeDL(options) as downloader:
                info = downloader.extract_info(request.url, download=True)
                video_path = Path(
                    info.get("requested_downloads", [{}])[0].get("filepath")
                    or info.get("filepath")
                    or downloader.prepare_filename(info)
                )
        except Exception as error:
            print(f"video_download_failed {type(error).__name__}", flush=True)
            raise HTTPException(status_code=422, detail="video_download_failed")

        if not video_path.exists():
            candidates = list(root.glob("source.*"))
            if not candidates:
                raise HTTPException(status_code=422, detail="video_missing")
            video_path = candidates[0]
        if video_path.stat().st_size > MAX_VIDEO_BYTES:
            raise HTTPException(status_code=413, detail="video_too_large")

        try:
            duration_text = _run([
                "ffprobe", "-v", "error", "-show_entries", "format=duration",
                "-of", "default=noprint_wrappers=1:nokey=1", str(video_path),
            ])
            duration = float(duration_text)
        except Exception:
            raise HTTPException(status_code=422, detail="duration_unavailable")
        if duration <= 0 or duration > MAX_DURATION_SECONDS:
            raise HTTPException(status_code=422, detail="duration_not_supported")

        frames_dir = root / "frames"
        frames_dir.mkdir()
        _run([
            "ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(video_path),
            "-vf", f"fps={FRAME_RATE},scale=768:-2:flags=lanczos",
            "-q:v", "5", str(frames_dir / "%05d.jpg"),
        ])
        selected = _select_frames(sorted(frames_dir.glob("*.jpg")))

        audio_path = root / "audio.mp3"
        try:
            _run([
                "ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(video_path),
                "-vn", "-ac", "1", "-ar", "16000", "-b:a", "48k",
                str(audio_path),
            ])
        except Exception:
            pass

        return {
            "duration_seconds": round(duration),
            "frames": [_encode_frame(path, second) for path, second in selected],
            "transcript": _transcribe(audio_path),
            "source_title": str(info.get("title") or "")[:1000],
            "source_description": str(info.get("description") or "")[:8000],
        }
