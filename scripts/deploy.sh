#!/usr/bin/env bash
# scripts/deploy.sh
# ─────────────────────────────────────────────────────────────────────────────
# Zero-downtime production deployment.
#
# Called by GitHub Actions CI with:
#   GHCR_OWNER=<github-org-or-username> IMAGE_TAG=<sha> bash scripts/deploy.sh
#
# Called manually for a hotfix:
#   GHCR_OWNER=myorg IMAGE_TAG=abc1234 bash scripts/deploy.sh
#
# Both IMAGE_TAG and GHCR_OWNER are injected by the CI workflow from
# github.repository_owner and the build job outputs — no placeholders.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

IMAGE_TAG="${IMAGE_TAG:-latest}"
GHCR_OWNER="${GHCR_OWNER:?GHCR_OWNER env var is required (your GitHub username or org)}"
REGISTRY="ghcr.io/${GHCR_OWNER}/dharmasthala"

echo "═══════════════════════════════════════════════════════"
echo "  Dharmasthala Events – Deployment  [tag: $IMAGE_TAG]"
echo "  Registry: $REGISTRY"
echo "  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "═══════════════════════════════════════════════════════"

# ── Track the previous image tag so we can roll back to it ───────────────────
PREV_BACKEND_ID=$(docker inspect --format='{{.Id}}' dharmasthala-backend:latest 2>/dev/null || echo "")
PREV_FRONTEND_ID=$(docker inspect --format='{{.Id}}' dharmasthala-frontend:latest 2>/dev/null || echo "")

rollback() {
    echo "❌ Deployment failed — rolling back to previous image..."
    if [ -n "$PREV_BACKEND_ID" ]; then
        docker tag "$PREV_BACKEND_ID"  dharmasthala-backend:latest
        docker compose up -d --no-deps --force-recreate backend
    fi
    if [ -n "$PREV_FRONTEND_ID" ]; then
        docker tag "$PREV_FRONTEND_ID" dharmasthala-frontend:latest
        docker compose up -d --no-deps --force-recreate frontend
    fi
    docker compose exec -T nginx nginx -s reload 2>/dev/null || true
    echo "↩ Rollback complete — previous version restored"
    exit 1
}
trap rollback ERR

# ── 1. Pre-deploy backup ──────────────────────────────────────────────────────
echo "→ Pre-deploy backup..."
bash scripts/backup.sh
echo "✅ Backup complete"

# ── 2. Pull new images ────────────────────────────────────────────────────────
echo "→ Pulling images (tag: $IMAGE_TAG)..."
docker pull "${REGISTRY}-backend:${IMAGE_TAG}"
docker pull "${REGISTRY}-frontend:${IMAGE_TAG}"
docker tag  "${REGISTRY}-backend:${IMAGE_TAG}"  dharmasthala-backend:latest
docker tag  "${REGISTRY}-frontend:${IMAGE_TAG}" dharmasthala-frontend:latest

# ── 3. Sync repo files from git ──────────────────────────────────────────────
# Only syncs nginx configs, scripts, compose files — .env is gitignored and safe
if [ -d .git ]; then
    git fetch --quiet origin main
    git reset --hard origin/main
    echo "✅ Config files synced from git"
fi

# ── 4. Validate nginx config ─────────────────────────────────────────────────
echo "→ Validating Nginx config..."
docker compose exec -T nginx nginx -t
echo "✅ Nginx config valid"

# ── 5. Rolling restart – backend first ───────────────────────────────────────
echo "→ Restarting backend..."
docker compose up -d --no-deps --force-recreate backend

TRIES=0
until docker compose exec -T backend \
    python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" 2>/dev/null; do
    TRIES=$((TRIES + 1))
    [ $TRIES -ge 12 ] && { echo "❌ Backend did not become healthy after 60s"; exit 1; }
    echo "   Waiting for backend... ($TRIES/12)"
    sleep 5
done
echo "✅ Backend healthy"

# ── 6. Rolling restart – frontend ────────────────────────────────────────────
echo "→ Restarting frontend..."
docker compose up -d --no-deps --force-recreate frontend
sleep 5
echo "✅ Frontend restarted"

# ── 7. Reload nginx ──────────────────────────────────────────────────────────
docker compose exec -T nginx nginx -s reload
echo "✅ Nginx reloaded"

# ── 8. Prune old images (keep last 24h) ──────────────────────────────────────
docker image prune -f --filter "until=24h"

# Disable rollback trap — deploy succeeded
trap - ERR

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ✅ Deployment successful!  [tag: $IMAGE_TAG]"
echo "  $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "═══════════════════════════════════════════════════════"
