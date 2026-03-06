#!/usr/bin/env bash
# scripts/renew-ssl.sh
# ─────────────────────────────────────────────────────────────────────────────
# Let's Encrypt certificate renewal.
# Run by cron twice daily; Certbot only renews when < 30 days remain.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting SSL renewal check..."

docker compose run --rm certbot renew --quiet

# Reload nginx to pick up renewed certs
if docker compose exec -T nginx nginx -t &>/dev/null; then
    docker compose exec -T nginx nginx -s reload
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Nginx reloaded with renewed certificates"
else
    echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ⚠️  Nginx config test failed – not reloading"
    exit 1
fi
