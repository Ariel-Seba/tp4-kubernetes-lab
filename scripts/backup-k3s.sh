#!/bin/bash

CLUSTER="curso-k8s"
BACKUP_DIR="$HOME/k3s-backups"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
DEST="$BACKUP_DIR/$TIMESTAMP"

mkdir -p "$DEST"

docker cp k3d-${CLUSTER}-server-0:/var/lib/rancher/k3s/server/db/state.db     "$DEST/state.db"
docker cp k3d-${CLUSTER}-server-0:/var/lib/rancher/k3s/server/db/state.db-shm "$DEST/state.db-shm"
docker cp k3d-${CLUSTER}-server-0:/var/lib/rancher/k3s/server/db/state.db-wal "$DEST/state.db-wal"

echo "Backup completado: $DEST"

# Retener solo los ultimos 7 backups
ls -dt "$BACKUP_DIR"/[0-9]*/ | tail -n +8 | xargs rm -rf
