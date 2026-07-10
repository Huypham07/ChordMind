from fastapi import Depends
from sqlalchemy.orm import Session
from app.infrastructure.db import get_session
from app.infrastructure.repository import SqlSongRepository
from app.infrastructure.slots import StubAnalysisSlot
from app.infrastructure.analysis.slot import OnnxAnalysisSlot
from app.application.analyze_song import AnalyzeSong

def get_repo(session: Session = Depends(get_session)) -> SqlSongRepository:
    return SqlSongRepository(session)

def get_analyze_song(repo: SqlSongRepository = Depends(get_repo)) -> AnalyzeSong:
    # A0 wires the stub slot here; swap StubAnalysisSlot for real slots in A1 without touching routes.
    return AnalyzeSong(repo, StubAnalysisSlot())

def get_file_analyzer(repo: SqlSongRepository = Depends(get_repo)) -> AnalyzeSong:
    # Separate from get_analyze_song: OnnxAnalysisSlot.run() raises NotImplementedError
    # for the YouTube flow, so the shared stub-backed dep must stay untouched.
    return AnalyzeSong(repo, OnnxAnalysisSlot("btc"))
