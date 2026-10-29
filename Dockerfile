# --- UI build ---------------------------------------------------------------
# The UI is static HTML/JS/CSS, identical for every CPU type, so it always builds on the
# builder's native platform. (npm under QEMU arm64 emulation crashes with an illegal instruction.)
FROM --platform=$BUILDPLATFORM node:22.15.0-alpine AS ui
WORKDIR /ui
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY frontend/ ./
RUN npm run build

# --- node runtime ---------------------------------------------------------------
FROM python:3.12.10-slim
LABEL org.opencontainers.image.source="https://github.com/ShreyasDr71/PeaSec" \
      org.opencontainers.image.description="P2PSec: peer-to-peer privileged access management for LANs"
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
    STATIC_DIR=/app/static DATA_DIR=/data UI_HOST=0.0.0.0 UI_PORT=8000 PEER_PORT=7600
WORKDIR /app
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY backend/p2psec ./p2psec
COPY --from=ui /ui/dist ./static
RUN useradd --system --uid 10001 p2psec && mkdir /data && chown p2psec /data
USER p2psec
VOLUME /data
EXPOSE 8000 7600 7601/udp
HEALTHCHECK --interval=15s --timeout=3s --start-period=20s \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/api/status')"
CMD ["python", "-m", "p2psec"]
