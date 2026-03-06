#!/usr/bin/env bash
# scripts/backup.sh
# ─────────────────────────────────────────────────────────────────────────────
# MongoDB backup with 30-day retention.
# Stores compressed dumps locally; optionally syncs to S3 / Backblaze B2.
# Runs daily via cron (see setup-server.sh).
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

# ── Config (inherit from .env) ────────────────────────────────────────────────
if [ -f .env ]; then
    export $(grep -v '^#' .env | grep -E 'MONGO_ROOT_USER|MONGO_ROOT_PASS|MONGO_DB' | xargs)
fi

BACKUP_DIR="/opt/dharmasthala/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_NAME="dharmasthala_${TIMESTAMP}"
RETENTION_DAYS=30

MONGO_USER="${MONGO_ROOT_USER:-mongoroot}"
MONGO_PASS="${MONGO_ROOT_PASS:-}"
MONGO_DB="${MONGO_DB:-dharmasthala_events}"

# Optional cloud backup
S3_BUCKET="${BACKUP_S3_BUCKET:-}"    # Set in .env: s3://your-bucket/backups
B2_BUCKET="${BACKUP_B2_BUCKET:-}"    # Set in .env: b2://your-bucket/backups

mkdir -p "$BACKUP_DIR"

echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Starting MongoDB backup → $BACKUP_NAME"

# ── Run mongodump inside the mongo container ──────────────────────────────────
docker compose exec -T mongo mongodump \
    --authenticationDatabase admin \
    --username "$MONGO_USER" \
    --password "$MONGO_PASS" \
    --db "$MONGO_DB" \
    --archive \
    --gzip \
    > "$BACKUP_DIR/${BACKUP_NAME}.archive.gz"

BACKUP_SIZE=$(du -sh "$BACKUP_DIR/${BACKUP_NAME}.archive.gz" | cut -f1)
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Backup complete: ${BACKUP_NAME}.archive.gz ($BACKUP_SIZE)"

# ── Optional: sync to AWS S3 ──────────────────────────────────────────────────
if [ -n "$S3_BUCKET" ]; then
    if command -v aws &>/dev/null; then
        aws s3 cp "$BACKUP_DIR/${BACKUP_NAME}.archive.gz" \
            "${S3_BUCKET}/${BACKUP_NAME}.archive.gz" \
            --storage-class STANDARD_IA
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Synced to S3: $S3_BUCKET"
    else
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ⚠️  aws CLI not found – skipping S3 sync"
    fi
fi

# ── Optional: sync to Backblaze B2 ───────────────────────────────────────────
if [ -n "$B2_BUCKET" ]; then
    if command -v b2 &>/dev/null; then
        b2 upload-file "${B2_BUCKET}" \
            "$BACKUP_DIR/${BACKUP_NAME}.archive.gz" \
            "${BACKUP_NAME}.archive.gz"
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Synced to B2: $B2_BUCKET"
    else
        echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] ⚠️  b2 CLI not found – skipping B2 sync"
    fi
fi

# ── Prune local backups older than RETENTION_DAYS ─────────────────────────────
DELETED=$(find "$BACKUP_DIR" -name "dharmasthala_*.archive.gz" \
    -mtime +${RETENTION_DAYS} -print -delete | wc -l)
echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] Pruned $DELETED backup(s) older than ${RETENTION_DAYS} days"

# ── Restore instructions ──────────────────────────────────────────────────────
# mongorestore --authenticationDatabase admin -u root -p pass \
#   --archive=dharmasthala_TIMESTAMP.archive.gz --gzip \
#   --nsFrom "dharmasthala_events.*" --nsTo "dharmasthala_events.*"
