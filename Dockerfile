FROM python:3.12-slim-trixie@sha256:5e2bdb1b0d542d5039cffb8181c65930093949194a65c365dfb1b0fe13a4fa5b AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PYTHONUTF8=1 \
    HOST=0.0.0.0 PORT=8086 DATABASE_PATH=/data/k-agora.sqlite3 SEED_DEMO=false
WORKDIR /app
RUN mkdir -p /data && chown 10001:10001 /data
COPY --chown=10001:10001 agora /app/agora
COPY --chown=10001:10001 static /app/static
COPY --chown=10001:10001 documents/2026-school-accounting-02/01-agendas-master-37.json /app/documents/2026-school-accounting-02/01-agendas-master-37.json
COPY --chown=10001:10001 data/sample-agendas.json /app/data/sample-agendas.json
COPY --chown=10001:10001 scripts/nas-preflight.py /app/scripts/nas-preflight.py
USER 10001:10001
HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=5 CMD python -c "import os,urllib.request; urllib.request.urlopen('http://127.0.0.1:'+os.environ['PORT']+'/api/health',timeout=3).read()"
CMD ["python", "-m", "agora.server"]

FROM runtime AS test
COPY --chown=10001:10001 tests /app/tests

FROM runtime AS production
