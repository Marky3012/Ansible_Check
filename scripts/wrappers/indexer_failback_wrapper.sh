#!/usr/bin/env bash
# indexer_failback_wrapper.sh — run ON the returning Wazuh-Indexer node
# Starts wazuh-indexer and waits until the JVM HTTP port is accepting connections.
# The Ansible play removes API exclusions AFTER this script succeeds.
#
# Exit codes: 0=success  1=runtime failure  2=preflight failure
# Required env vars:
#   INDEXER_SERVICE   — systemd unit name (default: wazuh-indexer)
#   INDEXER_HTTP_PORT — OpenSearch HTTP port (default: 9200)
#   JOIN_TIMEOUT      — seconds to wait for HTTP readiness (default: 120)

set -euo pipefail

INDEXER_SERVICE="${INDEXER_SERVICE:-wazuh-indexer}"
INDEXER_HTTP_PORT="${INDEXER_HTTP_PORT:-9200}"
JOIN_TIMEOUT="${JOIN_TIMEOUT:-120}"

log() { echo "[$(date -u +%FT%TZ)] $*"; }

if ! command -v systemctl &>/dev/null; then
  log "PREFLIGHT FAILED: systemctl not found"
  exit 2
fi

# ── start service ──────────────────────────────────────────────────────────────
if systemctl is-active --quiet "${INDEXER_SERVICE}"; then
  log "Service ${INDEXER_SERVICE} already running — checking HTTP readiness."
else
  log "Starting ${INDEXER_SERVICE}..."
  systemctl start "${INDEXER_SERVICE}"
fi

# ── wait for HTTP port ─────────────────────────────────────────────────────────
log "Waiting up to ${JOIN_TIMEOUT}s for port ${INDEXER_HTTP_PORT} to open..."
DEADLINE=$(( $(date +%s) + JOIN_TIMEOUT ))
while true; do
  if (( $(date +%s) >= DEADLINE )); then
    log "FAILED: port ${INDEXER_HTTP_PORT} not accepting connections after ${JOIN_TIMEOUT}s"
    exit 1
  fi
  if bash -c ">/dev/tcp/127.0.0.1/${INDEXER_HTTP_PORT}" 2>/dev/null; then
    break
  fi
  sleep 5
done

log "OK: port ${INDEXER_HTTP_PORT} open — node is up."
exit 0
