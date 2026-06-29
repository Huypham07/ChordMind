from datetime import datetime
from sqlalchemy import String, DateTime, JSON
from sqlalchemy.orm import Mapped, mapped_column
from app.infrastructure.db import Base

class SongRow(Base):
    __tablename__ = "songs"
    id: Mapped[str] = mapped_column(String, primary_key=True)
    youtube_id: Mapped[str] = mapped_column(String, index=True)
    title: Mapped[str] = mapped_column(String)
    analysis_json: Mapped[dict] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=datetime.utcnow)
