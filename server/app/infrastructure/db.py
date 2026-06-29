from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker
from app.config import get_settings

Base = declarative_base()
_engine = create_engine(get_settings().database_url, future=True)
SessionLocal = sessionmaker(bind=_engine, future=True)

def init_db():
    from app.infrastructure import orm  # noqa: F401  ensure tables are registered
    Base.metadata.create_all(_engine)

def get_session():
    with SessionLocal() as s:
        yield s
