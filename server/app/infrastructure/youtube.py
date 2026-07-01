import re

_PATTERNS = [r"v=([\w-]{11})", r"youtu\.be/([\w-]{11})", r"([\w-]{11})$"]

def parse_video_id(url: str) -> str:
    for p in _PATTERNS:
        m = re.search(p, url)
        if m:
            return m.group(1)
    raise ValueError(f"cannot parse video id from {url!r}")

def fetch_meta(video_id: str) -> tuple[str, float]:
    # ponytail: real metadata via yt-dlp; falls back to stub if it fails (A0 analysis is stubbed anyway).
    try:
        import yt_dlp
        with yt_dlp.YoutubeDL({"quiet": True, "skip_download": True}) as ydl:
            info = ydl.extract_info(f"https://youtu.be/{video_id}", download=False)
            return info.get("title", video_id), float(info.get("duration", 120.0))
    except Exception:
        return video_id, 120.0
