from fastapi import APIRouter, Depends, HTTPException
from app.api.schemas import SubmitRequest
from app.api.deps import get_repo, get_analyze_song
from app.application.analyze_song import AnalyzeSong
from app.infrastructure.repository import SqlSongRepository
from app.infrastructure import youtube

router = APIRouter()

@router.get("/health")
def health():
    return {"status": "ok"}

@router.post("/songs")
def submit_song(body: SubmitRequest, uc: AnalyzeSong = Depends(get_analyze_song)):
    vid = youtube.parse_video_id(body.url)
    title, duration = youtube.fetch_meta(vid)
    return uc.execute(vid, title, duration).to_dict()

@router.get("/songs/{youtube_id}")
def get_song(youtube_id: str, repo: SqlSongRepository = Depends(get_repo)):
    result = repo.get(youtube_id)
    if not result:
        raise HTTPException(404, "not analyzed yet")
    return result.to_dict()

@router.get("/songs")
def recent(repo: SqlSongRepository = Depends(get_repo)):
    return [{"youtubeId": yid, "title": t} for yid, t in repo.recent()]
