#!/bin/bash

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${0}")" && pwd -P)
PROJECT_DIR=$(dirname "${SCRIPT_DIR}")
SECRETS_FILE="${PROJECT_DIR}/terraform/secrets.enc.json"

NAMESPACE="postgres"
SERVICE="postgres-service"
NFS_SERVER="192.168.1.67"
NFS_PATH="/var/nfs/backups/postgres"

BACKUP_NAME=${1:-}

if [ -z "${BACKUP_NAME}" ]; then
    echo "Usage: ${0} <backup-file-name>"
    echo "Example: ${0} backup-2026-07-20-0000.sql.gz"
    exit 1
fi

echo "Reading postgres credentials from ${SECRETS_FILE}..."
POSTGRES_USER=$(sops -d --extract '["postgres_shared_username"]' "${SECRETS_FILE}")
POSTGRES_PASSWORD=$(sops -d --extract '["postgres_shared_password"]' "${SECRETS_FILE}")

POSTGRES_IMAGE=$(kubectl get pod -n "${NAMESPACE}" postgres-0 -o jsonpath='{.spec.containers[0].image}')

if [[ "${BACKUP_NAME}" == *.gz ]]; then
    CAT_CMD="gunzip -c /mnt/backup/${BACKUP_NAME}"
else
    CAT_CMD="cat /mnt/backup/${BACKUP_NAME}"
fi

read -rp "This will restore '${BACKUP_NAME}' into the live '${NAMESPACE}' database. Continue? [y/N] " CONFIRM
if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo "Restoring ${BACKUP_NAME} using ${POSTGRES_IMAGE}..."
kubectl run postgres-restore \
    --namespace "${NAMESPACE}" \
    --image "${POSTGRES_IMAGE}" \
    --restart=Never \
    --rm \
    -i \
    --overrides="$(cat <<EOF
{
  "spec": {
    "containers": [
      {
        "name": "postgres-restore",
        "image": "${POSTGRES_IMAGE}",
        "stdin": true,
        "env": [
          {"name": "PGPASSWORD", "value": "${POSTGRES_PASSWORD}"}
        ],
        "command": ["/bin/sh", "-c", "set -e; ${CAT_CMD} | psql -h ${SERVICE} -U ${POSTGRES_USER} -d postgres"],
        "volumeMounts": [
          {"name": "backup", "mountPath": "/mnt/backup"}
        ]
      }
    ],
    "volumes": [
      {"name": "backup", "nfs": {"server": "${NFS_SERVER}", "path": "${NFS_PATH}"}}
    ]
  }
}
EOF
)"

echo "Restore complete."
