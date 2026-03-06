#!/usr/bin/env bash
# scripts/init-ssl.sh
# ─────────────────────────────────────────────────────────────────────────────
# Obtain Let's Encrypt TLS certificate for the first time.
# Run ONCE after setup-server.sh and BEFORE starting the full stack.
# Requires: .env file with DOMAIN and CERTBOT_EMAIL set.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# Load domain from .env
if [ -f .env ]; then
    export $(grep -v '^#' .env | grep -E 'DOMAIN|CERTBOT_EMAIL' | xargs)
fi

DOMAIN="${DOMAIN:-}"
EMAIL="${CERTBOT_EMAIL:-}"

if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
    echo "❌ DOMAIN and CERTBOT_EMAIL must be set in .env"
    exit 1
fi

echo "🔐 Obtaining TLS certificate for $DOMAIN ..."

# Step 1: Start nginx with HTTP-only config to serve ACME challenge
# Temporarily replace the HTTPS config with the HTTP-only bootstrap config
cp nginx/conf.d/dharmasthala.conf nginx/conf.d/dharmasthala.conf.bak
cat > nginx/conf.d/dharmasthala.conf << EOF
server {
    listen 80;
    server_name $DOMAIN www.$DOMAIN;
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    location / { return 200 'OK'; add_header Content-Type text/plain; }
}
EOF

docker compose up -d nginx
sleep 5

# Step 2: Run certbot
docker compose --profile ssl-init run --rm certbot

# Step 3: Restore full nginx config
cp nginx/conf.d/dharmasthala.conf.bak nginx/conf.d/dharmasthala.conf

# Step 4: Reload nginx with HTTPS config
docker compose exec nginx nginx -s reload

echo "✅ SSL certificate obtained for $DOMAIN"
echo "   Certificate: /etc/letsencrypt/live/$DOMAIN/fullchain.pem"
echo "   Key:         /etc/letsencrypt/live/$DOMAIN/privkey.pem"
echo ""
echo "Now run: docker compose up -d"
