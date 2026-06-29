from fastapi import FastAPI
from app.infrastructure.db import init_db
from app.api.routes import router

app = FastAPI(title="ChordMind")

@app.on_event("startup")
def _startup():
    init_db()

app.include_router(router)
