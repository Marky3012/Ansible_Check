#!/usr/bin/env bash
# postgres_rejoin_wrapper.sh — run ON the old primary rejoining the cluster as standby
# Uses repmgr node rejoin with --force-rewind (pg_rewind + re-register in one step).
# Run AFTER the new primary is confirmed healthy.
#
# Exit codes: 0=success  1=runtime failure  2=preflight failure
# Required env vars:
#   REPMGR_CONF       — path to repmgr.conf (default: /etc/repmgr.conf)
#   REPMGR_USER       — repmgr superuser (default: repmgr)
#   NEW_PRIMARY_CONNINFO — libpq conninfo string for the new primary
#                          e.g. "host=172.21.x.x user=repmgr dbname=repmgr"
#   REJOIN_TIMEOUT    — seconds for replication catch-up check (default: 60)

set -euo pipefail

REPMGR_CONF="${REPMGR_CONF:-/etc/repmgr.conf}"
REPMGR_USER="${REPMGR_USER:-repmgr}"
NEW_PRIMARY_CONNINFO="${NEW_PRIMARY_CONNINFO:?NEW_PRIMARY_CONNINFO env var is required}"
REJOIN_TIMEOUT="${REJOIN_TIMEOUT:-60}"

log() { echo "[$(date -u +%FT%TZ)] $*"; }

# ── preflight ──────────────────────────────────────────────────────────────────
if ! command -v repmgr &>/dev/null; then
  log "PREFLIGHT FAILED: repmgr binary not found"
  exit 2
fi

if [[ ! -f "${REPMGR_CONF}" ]]; then
  log "PREFLIGHT FAILED: ${REPMGR_CONF} not found"
  exit 2
fi

# ── rejoin ─────────────────────────────────────────────────────────────────────
log "Rejoining cluster as standby (force-rewind) pointing to: ${NEW_PRIMARY_CONNINFO}"
su - "${REPMGR_USER}" -c \
  "repmgr -f '${REPMGR_CONF}' node rejoin \
    -d '${NEW_PRIMARY_CONNINFO}' \
    --force-rewind \
    --no-wait \
    --log-level INFO"

# ── wait for replication to start ─────────────────────────────────────────────
log "Waiting up to ${REJOIN_TIMEOUT}s for streaming replication to start..."
DEADLINE=$(( $(date +%s) + REJOIN_TIMEOUT ))
while true; do
  if (( $(date +%s) >= DEADLINE )); then
    log "FAILED: streaming replication not established after ${REJOIN_TIMEOUT}s"
    exit 1
  fi
  # pg_stat_wal_receiver row exists when streaming is active
  STREAMING=$(su - "${REPMGR_USER}" -c \
    "psql -At -c \"SELECT count(*) FROM pg_stat_wal_receiver WHERE status='streaming'\" repmgr 2>/dev/null" || echo "0")
  if [[ "${STREAMING}" == "1" ]]; then
    break
  fi
  sleep 5
done

log "OK: streaming replication established — node rejoined as standby."
exit 0
