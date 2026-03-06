# ── Stage 1: dependency builder ───────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build

# System deps needed only at build time
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc libssl-dev && \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --upgrade pip && \
    pip install --no-cache-dir --prefix=/install -r requirements.txt


# ── Stage 2: runtime image ─────────────────────────────────────────────────────
FROM python:3.12-slim AS runtime

LABEL maintainer="Dharmasthala Events Team"
LABEL org.opencontainers.image.title="dharmasthala-backend"
LABEL org.opencontainers.image.description="FastAPI backend for Dharmasthala Events"

# Security: run as non-root
RUN groupadd -r appgroup && useradd -r -g appgroup -d /app -s /sbin/nologin appuser

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /install /usr/local

# Copy application source
COPY --chown=appuser:appgroup . .

# Drop to non-root
USER appuser

# Expose app port (Nginx proxies this, never expose directly)
EXPOSE 8000

# Health check – used by Docker and orchestrators
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')"

# Production server: uvicorn with multiple workers
# Workers = (2 × CPU cores) + 1  →  adjust --workers per your server
CMD ["uvicorn", "main:app", \
     "--host", "0.0.0.0", \
     "--port", "8000", \
     "--workers", "4", \
     "--proxy-headers", \
     "--forwarded-allow-ips", "*", \
     "--access-log", \
     "--log-level", "info"]
