#!/bin/bash

set -euo pipefail

# Backup settings
SOURCE="/var/www/html/"
DEST="backuprecv@192.168.1.243"
KEY="/home/ubuntu/.ssh/week4_backup_ed25519"
BACKUP_BASE="/srv/backups/week4"

# Create timestamp
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_DIR="$BACKUP_BASE/backup-$TIMESTAMP"
TEMP_DIR="$BACKUP_BASE/.backup-$TIMESTAMP-incomplete"

# Log file
LOG_FILE="/home/ubuntu/viikko4/backup.log"

# SSH settings
SSH_CMD="ssh -i $KEY -o BatchMode=yes -o IdentitiesOnly=yes -o StrictHostKeyChecking=yes"

echo "Starting backup: $TIMESTAMP"

# Create temporary backup directory on Server B
if $SSH_CMD "$DEST" "mkdir -m 700 '$TEMP_DIR'" &&
   rsync -av --no-owner --no-group \
   --chmod=Du=rwx,Dgo=,Fu=rw,Fgo= \
   -e "$SSH_CMD" \
   "$SOURCE" "$DEST:$TEMP_DIR/" &&
   $SSH_CMD "$DEST" "mv '$TEMP_DIR' '$BACKUP_DIR'"
then
    echo "$(date -Is) SUCCESS: $BACKUP_DIR" >> "$LOG_FILE"
    echo "Backup completed successfully!"
else
    echo "$(date -Is) FAILED: $BACKUP_DIR" >> "$LOG_FILE"
    echo "Backup failed!"
    exit 1
fi
