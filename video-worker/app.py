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


def _download_video(raw_url: str, root: Path) -> tuple[dict, Path]:
    output_template = str(root / "source.%(ext)s")
    base_options = {
        "format": "bv*[height<=720]+ba/b[height<=720]/b",
        "merge_output_format": "mp4",
        "outtmpl": output_template,
        "noplaylist": True,
        "quiet": True,
        "no_warnings": True,
        "max_filesize": MAX_VIDEO_BYTES,
        "socket_timeout": 25,
        "retries": 3,
        "fragment_retries": 3,
        "http_headers": {
            "User-Agent": (
                "Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) "
                "AppleWebKit/537.36 Chrome/131.0 Mobile Safari/537.36"
            ),
            "Accept-Language": "ja-JP,ja;q=0.9,en-US;q=0.8,en;q=0.7",
        },
    }
    proxy = os.getenv("YTDLP_PROXY", "").strip()
    if proxy:
        base_options["proxy"] = proxy
    cookies_b64 = os.getenv("YTDLP_COOKIES_B64", "").strip()
    if cookies_b64:
        try:
            cookies_path = root / "cookies.txt"
            cookies_path.write_bytes(base64.b64decode(cookies_b64, validate=True))
            base_options["cookiefile"] = str(cookies_path)
        except Exception:
            print("video_cookies_invalid", flush=True)

    attempts = [
        ("chrome_impersonation", {"impersonate": "chrome"}),
        (
            "chrome_impersonation_mobile_api",
            {
                "impersonate": "chrome",
                "extractor_args": {
                    "tiktok": {
                        "api_hostname": ["api22-normal-c-useast2a.tiktokv.com"],
                    }
                },
            },
        ),
        ("default", {}),
        (
            "tiktok_mobile_api",
            {
                "extractor_args": {
                    "tiktok": {
                        "api_hostname": ["api22-normal-c-useast2a.tiktokv.com"],
                    }
                }
            },
        ),
    ]
    last_error = "unknown"
    for label, overrides in attempts:
        options = {**base_options, **overrides}
        try:
            with YoutubeDL(options) as downloader:
                info = downloader.extract_info(raw_url, download=True)
                video_path = Path(
                    info.get("requested_downloads", [{}])[0].get("filepath")
                    or info.get("filepath")
                    or downloader.prepare_filename(info)
                )
            if not video_path.exists():
                candidates = [
                    path for path in root.glob("source.*")
                    if path.suffix not in {".part", ".ytdl"}
                ]
                if not candidates:
                    raise RuntimeError("download_completed_without_file")
                video_path = max(candidates, key=lambda path: path.stat().st_size)
            print(f"video_download_succeeded strategy={label}", flush=True)
            return info, video_path
        except Exception as error:
            last_error = " ".join(str(error).split())[:1200]
            print(
                f"video_download_attempt_failed strategy={label} detail={last_error}",
                flush=True,
            )
            for partial in root.glob("source.*"):
                try:
                    partial.unlink()
                except OSError:
                    pass
    raise RuntimeError(last_error)


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
        try:
            info, video_path = _download_video(request.url, root)
        except Exception as error:
            detail = " ".join(str(error).split())[:500]
            print(f"video_download_failed detail={detail}", flush=True)
            raise HTTPException(
                status_code=422,
                detail={"code": "video_download_failed", "reason": detail},
            )
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
