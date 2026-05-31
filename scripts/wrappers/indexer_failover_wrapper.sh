#!/usr/bin/env bash
# indexer_failover_wrapper.sh — run ON the failing Wazuh-Indexer node
# Stops the wazuh-indexer service cleanly so OpenSearch marks it gone.
# The Ansible play handles API-level fencing (voting exclusion, shard drain)
# BEFORE calling this script.
#
# Exit codes: 0=success  1=runtime failure  2=preflight failure
# Required env vars (set by Ansible):
#   INDEXER_SERVICE   — systemd unit name (default: wazuh-indexer)
#   STOP_TIMEOUT      — seconds to wait for graceful stop (default: 60)

set -euo pipefail

INDEXER_SERVICE="${INDEXER_SERVICE:-wazuh-indexer}"
STOP_TIMEOUT="${STOP_TIMEOUT:-60}"

log() { echo "[$(date -u +%FT%TZ)] $*"; }

# ── preflight ──────────────────────────────────────────────────────────────────
if ! command -v systemctl &>/dev/null; then
  log "PREFLIGHT FAILED: systemctl not found"
  exit 2
fi

# ── stop service ───────────────────────────────────────────────────────────────
log "Stopping ${INDEXER_SERVICE} (timeout: ${STOP_TIMEOUT}s)..."

if ! systemctl is-active --quiet "${INDEXER_SERVICE}"; then
  log "Service ${INDEXER_SERVICE} is already stopped — nothing to do."
  exit 0
fi

systemctl stop "${INDEXER_SERVICE}" --no-block
DEADLINE=$(( $(date +%s) + STOP_TIMEOUT ))
while systemctl is-active --quiet "${INDEXER_SERVICE}"; do
  if (( $(date +%s) >= DEADLINE )); then
    log "FAILED: ${INDEXER_SERVICE} did not stop within ${STOP_TIMEOUT}s — sending SIGKILL"
    systemctl kill --kill-who=all --signal=SIGKILL "${INDEXER_SERVICE}" || true
    sleep 2
    break
  fi
  sleep 2
done

if systemctl is-active --quiet "${INDEXER_SERVICE}"; then
  log "FAILED: ${INDEXER_SERVICE} still active after kill attempt"
  exit 1
fi

log "OK: ${INDEXER_SERVICE} stopped."
exit 0
