#!/bin/sh
# Ships the Squid access log and every run's summary.json to zimaboard over
# NFS. Never deletes or truncates anything at the destination - a sandbox
# that keeps its own history is not evidence.
set -e

DEST=/mnt/agent-log-backup
mkdir -p "$DEST/summaries"

# --no-owner --no-group: zimaboard's export root-squashes NFS clients, so
# preserving ownership (part of plain -a) fails with "Operation not
# permitted" even though the content itself transfers fine.
RSYNC="rsync -rlt --no-owner --no-group"

$RSYNC /srv/agent/log/squid-access.log "$DEST/squid-access.log"

for f in /srv/runs/*/summary.json; do
  [ -f "$f" ] || continue
  run_id=$(basename "$(dirname "$f")")
  mkdir -p "$DEST/summaries/$run_id"
  $RSYNC "$f" "$DEST/summaries/$run_id/summary.json"
done
