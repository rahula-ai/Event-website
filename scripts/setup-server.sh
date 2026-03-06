#!/usr/bin/env bash
# scripts/setup-server.sh
# ─────────────────────────────────────────────────────────────────────────────
# One-time setup for a fresh Ubuntu 22.04 / 24.04 VPS
# Run as root: bash setup-server.sh
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

APP_USER="dharmasthala"
APP_DIR="/opt/dharmasthala"
DEPLOY_SSH_PORT=22   # Change to your SSH port if non-standard

echo "═══════════════════════════════════════════════════════"
echo "  Dharmasthala Events – Server Setup"
echo "═══════════════════════════════════════════════════════"

# ── 1. System updates ─────────────────────────────────────────────────────────
apt-get update -y && apt-get upgrade -y
apt-get install -y \
    curl wget git ufw fail2ban unattended-upgrades \
    ca-certificates gnupg lsb-release openssl

# ── 2. Automatic security updates ────────────────────────────────────────────
cat > /etc/apt/apt.conf.d/50unattended-upgrades << 'EOF'
Unattended-Upgrade::Allowed-Origins { "${distro_id}:${distro_codename}-security"; };
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "03:00";
EOF
systemctl enable unattended-upgrades --now

# ── 3. Docker ────────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
        gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
        https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
        > /etc/apt/sources.list.d/docker.list
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    systemctl enable docker --now
    echo "✅ Docker installed"
else
    echo "✓  Docker already present"
fi

# ── 4. Application user ───────────────────────────────────────────────────────
if ! id "$APP_USER" &>/dev/null; then
    useradd -m -s /bin/bash -G docker "$APP_USER"
    echo "✅ User $APP_USER created and added to docker group"
fi

# ── 5. Application directory ─────────────────────────────────────────────────
mkdir -p "$APP_DIR"
chown "$APP_USER:$APP_USER" "$APP_DIR"

# ── 6. Firewall (UFW) ────────────────────────────────────────────────────────
ufw default deny incoming
ufw default allow outgoing
ufw allow "$DEPLOY_SSH_PORT/tcp" comment "SSH"
ufw allow 80/tcp  comment "HTTP"
ufw allow 443/tcp comment "HTTPS"
ufw --force enable
echo "✅ UFW firewall configured"

# ── 7. Fail2ban ───────────────────────────────────────────────────────────────
cat > /etc/fail2ban/jail.local << 'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
backend  = systemd

[sshd]
enabled = true
port    = ssh

[nginx-http-auth]
enabled = true

[nginx-limit-req]
enabled  = true
filter   = nginx-limit-req
logpath  = /var/log/nginx/error.log
maxretry = 10
EOF
systemctl enable fail2ban --now
echo "✅ Fail2ban configured"

# ── 8. Generate DH params for Nginx TLS ──────────────────────────────────────
DHPARAM_PATH="$APP_DIR/nginx/ssl/dhparam.pem"
if [ ! -f "$DHPARAM_PATH" ]; then
    mkdir -p "$APP_DIR/nginx/ssl"
    echo "Generating 4096-bit DH parameters (this takes a few minutes)..."
    openssl dhparam -out "$DHPARAM_PATH" 4096
    chown "$APP_USER:$APP_USER" "$DHPARAM_PATH"
    chmod 640 "$DHPARAM_PATH"
    echo "✅ DH parameters generated"
fi

# ── 9. Docker log rotation ────────────────────────────────────────────────────
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "5"
  },
  "live-restore": true
}
EOF
systemctl reload docker

# ── 10. Install cron jobs ─────────────────────────────────────────────────────
CRON_FILE="/etc/cron.d/dharmasthala"
cat > "$CRON_FILE" << EOF
# Dharmasthala Events – Scheduled Tasks
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

# MongoDB backup – daily at 2 AM
0 2 * * * $APP_USER $APP_DIR/scripts/backup.sh >> /var/log/dharmasthala-backup.log 2>&1

# SSL renewal check – twice daily (Certbot is idempotent)
0 0,12 * * * root $APP_DIR/scripts/renew-ssl.sh >> /var/log/dharmasthala-ssl.log 2>&1

# Docker prune – weekly (Sunday 3 AM) – reclaim disk space
0 3 * * 0 $APP_USER docker system prune -f >> /var/log/dharmasthala-prune.log 2>&1
EOF
chmod 644 "$CRON_FILE"
echo "✅ Cron jobs installed"

echo ""
echo "═══════════════════════════════════════════════════════"
echo "  ✅ Server setup complete!"
echo ""
echo "  Next steps:"
echo "  1. su - $APP_USER"
echo "  2. cd $APP_DIR"
echo "  3. git clone <your-repo> ."
echo "  4. cp .env.example .env && nano .env"
echo "  5. bash scripts/init-ssl.sh    (obtain TLS certificate)"
echo "  6. docker compose up -d"
echo "═══════════════════════════════════════════════════════"
