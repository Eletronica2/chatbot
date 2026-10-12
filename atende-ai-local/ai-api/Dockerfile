FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HOME=/models/hf \
    TOKENIZERS_PARALLELISM=false \
    OMP_NUM_THREADS=4

WORKDIR /srv
COPY requirements.txt .
RUN pip install --upgrade pip && pip install -r requirements.txt

RUN useradd --uid 10001 --create-home app && mkdir -p /models/hf && chown -R app:app /models
COPY --chown=app:app app ./app
COPY --chown=app:app tests ./tests
COPY --chown=app:app bench ./bench
COPY --chown=app:app fixtures ./fixtures

USER app
EXPOSE 8100
HEALTHCHECK --interval=30s --timeout=5s --start-period=180s --retries=3 \
  CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8100/health', timeout=3).status == 200 else 1)"
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8100", "--workers", "1", "--no-access-log"]
