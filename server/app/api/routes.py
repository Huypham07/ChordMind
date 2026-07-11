import tempfile, os, uuid
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Form
from app.api.schemas import SubmitRequest
from app.api.deps import get_repo, get_analyze_song, get_file_analyzer
from app.application.analyze_song import AnalyzeSong
from app.domain.ports import SongRepository
from app.infrastructure import youtube

router = APIRouter()

@router.get("/health")
def health():
    return {"status": "ok"}

@router.post("/songs")
def submit_song(body: SubmitRequest, uc: AnalyzeSong = Depends(get_analyze_song)):
    try:
        vid = youtube.parse_video_id(body.url)
    except ValueError:
        raise HTTPException(status_code=400, detail="invalid YouTube URL")
    title, duration = youtube.fetch_meta(vid)
    return uc.execute(vid, title, duration).to_dict()

@router.post("/songs/analyze-file")
async def analyze_file(file: UploadFile = File(...), title: str = Form(""),
                       uc: AnalyzeSong = Depends(get_file_analyzer)):
    suffix = os.path.splitext(file.filename or "")[1] or ".wav"
    tmp = os.path.join(tempfile.gettempdir(), f"cm_{uuid.uuid4().hex}{suffix}")
    try:
        with open(tmp, "wb") as f:
            f.write(await file.read())
        song_id = uuid.uuid4().hex  # storage/versioning is a later sub-project
        return uc.analyze_file(song_id, title, tmp).to_dict()
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)

@router.get("/songs/{youtube_id}")
def get_song(youtube_id: str, repo: SongRepository = Depends(get_repo)):
    result = repo.get(youtube_id)
    if not result:
        raise HTTPException(404, "not analyzed yet")
    return result.to_dict()

@router.get("/songs")
def recent(repo: SongRepository = Depends(get_repo)):
    return [{"youtubeId": yid, "title": t} for yid, t in repo.recent()]
