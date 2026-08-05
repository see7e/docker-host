#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

BACKUP_SCRIPT="$SCRIPT_DIR/docker_backup.sh"

chmod +x "$BACKUP_SCRIPT"

(crontab -l 2>/dev/null | grep -v docker_backup.sh; cat <<EOF
# Docker monitoring backup
0 3 * * * $BACKUP_SCRIPT >/dev/null 2>&1
EOF
) | crontab -

echo "Cron job installed."

echo
echo "Current crontab:"
crontab -l
