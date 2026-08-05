#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <backup-directory>"
    exit 1
fi

BACKUP="$1"

COMPOSE_DIR="/opt/docker/compose/monitoring"

PROMETHEUS_DATA="/var/lib/docker-services/prometheus"
GRAFANA_DATA="/var/lib/docker-services/grafana"

cd "$COMPOSE_DIR"

docker compose stop prometheus grafana

rm -rf "$PROMETHEUS_DATA"/*
rm -rf "$GRAFANA_DATA"/*

tar -xzf "$BACKUP/prometheus.tar.gz" -C "$PROMETHEUS_DATA"
tar -xzf "$BACKUP/grafana.tar.gz" -C "$GRAFANA_DATA"

docker compose start prometheus grafana