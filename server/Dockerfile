FROM python:3.12-slim
WORKDIR /srv

# ponytail: deps mirrored from pyproject.toml [project].dependencies — keep in sync.
RUN pip install --no-cache-dir \
    fastapi "uvicorn[standard]" "sqlalchemy>=2" "psycopg[binary]" \
    "pydantic>=2" pydantic-settings yt-dlp

COPY app ./app

EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
