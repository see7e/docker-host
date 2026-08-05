#!/usr/bin/env bash
set -Eeuo pipefail

########################################
# Configuration
########################################

COMPOSE_DIR="/opt/docker/compose/monitoring"

PROMETHEUS_DATA="/var/lib/docker-services/prometheus"
GRAFANA_DATA="/var/lib/docker-services/grafana"

BACKUP_ROOT="/mnt/omv/backups/docker"

RETENTION_DAYS=14

DATE=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_DIR="$BACKUP_ROOT/$DATE"

LOGFILE="$BACKUP_ROOT/backup.log"

########################################

log() {
    echo "[$(date '+%F %T')] $*" | tee -a "$LOGFILE"
}

mkdir -p "$BACKUP_DIR"

log "Stopping monitoring stack..."

cd "$COMPOSE_DIR"
docker compose stop prometheus grafana

log "Backing up Prometheus..."

tar -C "$PROMETHEUS_DATA" \
    -czf "$BACKUP_DIR/prometheus.tar.gz" .

log "Backing up Grafana..."

tar -C "$GRAFANA_DATA" \
    -czf "$BACKUP_DIR/grafana.tar.gz" .

log "Starting monitoring stack..."

docker compose start prometheus grafana

log "Removing backups older than ${RETENTION_DAYS} days..."

find "$BACKUP_ROOT" \
    -mindepth 1 \
    -maxdepth 1 \
    -type d \
    -mtime +"$RETENTION_DAYS" \
    -exec rm -rf {} +

log "Backup completed successfully."
