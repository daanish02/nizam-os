"""Fetch YouTube transcripts via three-tier fallback.

Tier 1: youtube-transcript-api (fastest, no key needed)
Tier 2: yt-dlp subtitle download (more browser-like, separate IP path)
Tier 3: YouTube Data API v3 captions (official, needs YOUTUBE_API_KEY)
"""

import os
import re
import subprocess
import tempfile
import time
from pathlib import Path


def _extract_video_id(url_or_id: str) -> str:
    url_or_id = url_or_id.strip()
    for pattern in [
        r'(?:v=|youtu\.be/|shorts/|embed/|live/)([a-zA-Z0-9_-]{11})',
        r'^([a-zA-Z0-9_-]{11})$',
    ]:
        m = re.search(pattern, url_or_id)
        if m:
            return m.group(1)
    return url_or_id


def _is_blocked(msg: str) -> bool:
    """Check for YouTube bot-block signals in an error message before attempting parse.

    Detects IP bans, HTTP 429/403 rate-limit responses, and explicit block wording.
    """
    return any(k in msg for k in ("ip", "block", "429", "too many", "forbidden", "403"))


def _parse_vtt(path: str) -> str:
    """Strip VTT markup and deduplicate overlapping lines."""
    tag_re = re.compile(r"<[^>]+>")
    seen: set[str] = set()
    lines: list[str] = []
    for raw in Path(path).read_text(errors="replace").splitlines():
        raw = raw.strip()
        if not raw or raw.startswith("WEBVTT") or "-->" in raw or re.match(r"^\d+$", raw):
            continue
        clean = tag_re.sub("", raw).strip()
        if clean and clean not in seen:
            seen.add(clean)
            lines.append(clean)
    return " ".join(lines)


# ---------------------------------------------------------------------------
# Tier 1 — youtube-transcript-api
# ---------------------------------------------------------------------------

def _tier1(video_id: str, languages: list[str]) -> dict:
    """Fetch via youtube-transcript-api (no API key). Returns transcript dict on success, error dict on failure."""
    from youtube_transcript_api import YouTubeTranscriptApi

    api = YouTubeTranscriptApi()
    last_err = ""

    for attempt in range(3):
        try:
            segments = api.fetch(video_id, languages=languages)
            segs = [{"text": s.text, "start": s.start, "duration": s.duration} for s in segments]
            full_text = " ".join(s["text"] for s in segs)
            total = segs[-1]["start"] + segs[-1]["duration"] if segs else 0
            return {
                "video_id": video_id,
                "full_text": full_text,
                "duration_seconds": round(total),
                "segment_count": len(segs),
                "source": "transcript-api",
            }
        except Exception as exc:
            last_err = str(exc)
            msg = last_err.lower()
            if "disabled" in msg:
                return {"error": "Transcripts are disabled for this video.", "video_id": video_id}
            if "no transcript" in msg:
                return {"error": "No English transcript found.", "video_id": video_id}
            if _is_blocked(msg) or attempt == 2:
                break
            time.sleep(1.5)

    return {"error": last_err, "video_id": video_id, "_blocked": _is_blocked(last_err.lower())}


# ---------------------------------------------------------------------------
# Tier 2 — yt-dlp subtitle download
# ---------------------------------------------------------------------------

def _tier2(video_id: str) -> dict:
    """Fetch via yt-dlp subtitle download (browser-like path). Returns parsed VTT dict on success, error dict on failure."""
    url = f"https://www.youtube.com/watch?v={video_id}"
    cookies_file = os.environ.get("YOUTUBE_COOKIES_FILE", "")

    # Find node runtime for yt-dlp JS challenge solving
    import shutil
    node_path = shutil.which("node") or ""

    with tempfile.TemporaryDirectory() as tmpdir:
        cmd = [
            "yt-dlp",
            "--ignore-config",
            "--write-auto-subs",
            "--sub-langs", "en",
            "--skip-download",
            "--sub-format", "vtt",
            "--no-playlist",
            "--quiet",
            "--no-warnings",
            "--remote-components", "ejs:github",
            "-o", f"{tmpdir}/%(id)s.%(ext)s",
        ]
        if node_path:
            cmd += ["--js-runtimes", f"node:{node_path}"]
        if cookies_file and Path(cookies_file).is_file():
            cmd += ["--cookies", cookies_file]
        cmd.append(url)
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
        except FileNotFoundError:
            return {"error": "yt-dlp not installed", "video_id": video_id}
        except subprocess.TimeoutExpired:
            return {"error": "yt-dlp timed out", "video_id": video_id}

        vtt_files = list(Path(tmpdir).glob("*.vtt"))
        if not vtt_files:
            stderr = proc.stderr.lower()
            if "blocked" in stderr or "403" in stderr:
                return {"error": "yt-dlp: IP blocked", "video_id": video_id}
            return {"error": f"yt-dlp: no subtitles found. {proc.stderr[:200]}", "video_id": video_id}

        text = _parse_vtt(str(vtt_files[0]))
        if not text:
            return {"error": "yt-dlp: VTT was empty after parsing", "video_id": video_id}

        return {
            "video_id": video_id,
            "full_text": text,
            "source": "yt-dlp",
        }


# ---------------------------------------------------------------------------
# Tier 3 — YouTube Data API v3
# ---------------------------------------------------------------------------

def _tier3(video_id: str) -> dict:
    """Fetch via YouTube Data API v3 (requires YOUTUBE_API_KEY). Returns caption or metadata dict on success, error dict on failure."""
    import httpx

    api_key = os.environ.get("YOUTUBE_API_KEY", "")
    if not api_key:
        return {"error": "YOUTUBE_API_KEY not set", "video_id": video_id}

    base = "https://www.googleapis.com/youtube/v3"

    # Always fetch video metadata (title, description, channel) — works with API key
    metadata: dict = {}
    try:
        r = httpx.get(
            f"{base}/videos",
            params={"id": video_id, "part": "snippet,contentDetails", "key": api_key},
            timeout=15,
        )
        r.raise_for_status()
        items = r.json().get("items", [])
        if items:
            s = items[0]["snippet"]
            metadata = {
                "title": s.get("title", ""),
                "channel": s.get("channelTitle", ""),
                "description": s.get("description", ""),
                "published_at": s.get("publishedAt", ""),
            }
    except Exception as exc:
        return {"error": f"YouTube API videos.list failed: {exc}", "video_id": video_id}

    if not metadata:
        return {"error": "Video not found via YouTube API", "video_id": video_id}

    # Try captions list
    tracks = []
    try:
        r = httpx.get(
            f"{base}/captions",
            params={"videoId": video_id, "part": "snippet", "key": api_key},
            timeout=15,
        )
        if r.status_code == 200:
            tracks = r.json().get("items", [])
    except Exception:
        pass

    # Try caption download (requires OAuth — will 401 for most keys, but worth trying)
    for t in tracks:
        lang = t.get("snippet", {}).get("language", "")
        if not lang.startswith("en"):
            continue
        try:
            r = httpx.get(
                f"{base}/captions/{t['id']}",
                params={"key": api_key, "tfmt": "vtt"},
                timeout=20,
            )
            if r.status_code == 200 and "WEBVTT" in r.text:
                tag_re = re.compile(r"<[^>]+>")
                seen: set[str] = set()
                lines: list[str] = []
                for raw in r.text.splitlines():
                    raw = raw.strip()
                    if not raw or raw.startswith("WEBVTT") or "-->" in raw:
                        continue
                    clean = tag_re.sub("", raw).strip()
                    if clean and clean not in seen:
                        seen.add(clean)
                        lines.append(clean)
                full_text = " ".join(lines)
                if full_text:
                    return {
                        "video_id": video_id,
                        "full_text": full_text,
                        "source": "youtube-api-v3-captions",
                        "title": metadata["title"],
                        "channel": metadata["channel"],
                    }
        except Exception:
            continue

    # Caption download unavailable — fall back to description as content
    description = metadata.get("description", "").strip()
    if not description:
        return {"error": "YouTube API: no caption access and no description", "video_id": video_id}

    title = metadata["title"]
    channel = metadata["channel"]
    full_text = f"{title}\n\nChannel: {channel}\n\nDescription:\n{description}"

    return {
        "video_id": video_id,
        "full_text": full_text,
        "source": "youtube-api-v3-metadata",
        "title": title,
        "channel": channel,
        "warning": "Full transcript unavailable — content is title + description only. Mark confidence=low.",
    }


# ---------------------------------------------------------------------------
# Public entry point
# ---------------------------------------------------------------------------

def fetch_transcript(url: str, languages: list[str] | None = None) -> dict:
    """Fetch YouTube transcript via three-tier fallback.

    Returns dict with video_id + full_text on success, or error on total failure.
    """
    video_id = _extract_video_id(url)
    langs = languages or ["en"]

    result = _tier1(video_id, langs)
    if "error" not in result:
        return result

    result2 = _tier2(video_id)
    if "error" not in result2:
        return result2

    result3 = _tier3(video_id)
    if "error" not in result3:
        return result3

    return {
        "error": "All transcript methods failed.",
        "video_id": video_id,
        "tier1": result.get("error"),
        "tier2": result2.get("error"),
        "tier3": result3.get("error"),
    }
