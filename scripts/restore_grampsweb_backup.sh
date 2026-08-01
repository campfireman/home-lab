#!/bin/bash

set -euo pipefail

NAMESPACE="grampsweb"
DEPLOYMENT="grampsweb"
PVC="grampsweb-pvc"
NFS_SERVER="192.168.1.67"
NFS_PATH="/var/nfs/backups/grampsweb"

BACKUP_NAME=${1:-}

if [ -z "${BACKUP_NAME}" ]; then
    echo "Usage: ${0} <backup-file-name>"
    echo "Example: ${0} grampsweb-2026-08-01-0300.tar.gz"
    exit 1
fi

IMAGE=$(kubectl get deployment "${DEPLOYMENT}" -n "${NAMESPACE}" -o jsonpath='{.spec.template.spec.containers[0].image}')

read -rp "This will scale '${DEPLOYMENT}' to 0, wipe its current users/secret/grampsdb/media data, and restore '${BACKUP_NAME}'. Continue? [y/N] " CONFIRM
if [[ ! "${CONFIRM}" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 1
fi

echo "Scaling ${DEPLOYMENT} down..."
kubectl scale deployment "${DEPLOYMENT}" -n "${NAMESPACE}" --replicas=0
kubectl wait --for=delete pod -n "${NAMESPACE}" -l app=grampsweb --timeout=120s

echo "Restoring ${BACKUP_NAME} using ${IMAGE}..."
kubectl run grampsweb-restore \
    --namespace "${NAMESPACE}" \
    --image "${IMAGE}" \
    --restart=Never \
    --rm \
    -i \
    --overrides="$(cat <<EOF
{
  "spec": {
    "containers": [
      {
        "name": "grampsweb-restore",
        "image": "${IMAGE}",
        "stdin": true,
        "command": ["/bin/sh", "-c", "set -e; rm -rf /restore/users /restore/secret /restore/grampsdb /restore/media; tar -xzf /mnt/backup/${BACKUP_NAME} -C /restore; echo Restore extracted."],
        "volumeMounts": [
          {"name": "data", "mountPath": "/restore"},
          {"name": "backup", "mountPath": "/mnt/backup", "readOnly": true}
        ]
      }
    ],
    "volumes": [
      {"name": "data", "persistentVolumeClaim": {"claimName": "${PVC}"}},
      {"name": "backup", "nfs": {"server": "${NFS_SERVER}", "path": "${NFS_PATH}"}}
    ]
  }
}
EOF
)"

echo "Scaling ${DEPLOYMENT} back up..."
kubectl scale deployment "${DEPLOYMENT}" -n "${NAMESPACE}" --replicas=1

echo "Restore complete. Verify via the grampsweb UI once the pod is ready."
