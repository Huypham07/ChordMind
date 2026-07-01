from pydantic_settings import BaseSettings
from functools import lru_cache

class Settings(BaseSettings):
    database_url: str = "postgresql+psycopg://chordmind:chordmind@localhost:5432/chordmind"

@lru_cache
def get_settings() -> Settings:
    return Settings()
