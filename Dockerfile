# Industrial IoT Data Hub / TiTiSwitch platform - the container image (Linux, also WSL 2).
#
#   Production (hub + PostgreSQL/TimescaleDB + EMQX + Caddy HTTPS): deploy/docker-compose.yml
#   Single plant, no device broker:                                   docker-compose.yml
#   Guide (Persian): docs/fa/install-docker-wsl.md
#
# One image runs everything: the API, the engineering dashboard (/), the customer web app (/app/),
# the maker panel (/maker/), the drivers, the device ports. Configuration is mounted at
# /app/config, secrets come from the environment, data lives in volumes. Runs as an unprivileged
# user. Migrations are applied by hub-api at start-up.
FROM python:3.12-slim-trixie

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    HUB_HOME=/app

# pg_dump / pg_restore of the same major version as the database (TimescaleDB on PostgreSQL 17)
# for the nightly backups and restores; tini reaps processes and forwards signals
RUN apt-get update \
    && apt-get install -y --no-install-recommends postgresql-client-17 tini \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
# a proxy for pip only (deploy/.env BUILD_PROXY), during the build; not kept in the image
ARG PIP_PROXY=""
# dependencies first (a cached layer): exactly the locked, audited versions
COPY requirements.lock ./
RUN pip install -r requirements.lock

COPY pyproject.toml README.md .env.example ./
COPY hub ./hub
COPY backend ./backend
COPY simulators ./simulators
COPY db ./db
COPY frontend ./frontend
COPY app ./app
COPY maker ./maker
COPY config ./config
RUN pip install --no-deps . \
    && useradd --system --uid 10001 --home-dir /app --shell /usr/sbin/nologin hub \
    && mkdir -p /app/logs /app/backups /app/pki /app/spool /app/certs /app/config/devices \
    && chown -R hub:hub /app/logs /app/backups /app/pki /app/spool /app/config \
    && usermod -aG dialout hub              # USB serial adapters (Modbus RTU) when mapped in

USER hub
EXPOSE 8000 7000
ENV HUB_HOST=0.0.0.0 \
    HUB_PORT=8000 \
    HUB_CONFIG_DIR=/app/config \
    HUB_LOG_FILE=/app/logs/hub.log \
    HUB_BACKUP_DIR=/app/backups \
    HUB_PG_DUMP=/usr/bin/pg_dump \
    HUB_PKI_DIR=/app/pki \
    HUB_SPOOL_DIR=/app/spool

HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD python -c "import urllib.request,sys; sys.exit(0 if urllib.request.urlopen('http://127.0.0.1:8000/api/health', timeout=4).status == 200 else 1)"

ENTRYPOINT ["/usr/bin/tini", "--"]
CMD ["hub-api"]
