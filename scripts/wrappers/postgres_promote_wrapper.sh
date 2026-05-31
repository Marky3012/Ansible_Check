#!/usr/bin/env bash
# postgres_promote_wrapper.sh — run ON the repmgr standby being promoted to primary
# Uses repmgr to promote (which calls pg_promote + updates repmgr metadata atomically).
# The Ansible play MUST fence (stop + verify) the old primary BEFORE calling this.
#
# Exit codes: 0=success  1=runtime failure  2=preflight failure
# Required env vars:
#   REPMGR_CONF       — path to repmgr.conf (default: /etc/repmgr.conf)
#   REPMGR_USER       — repmgr superuser (default: repmgr)
#   PG_ISREADY_TIMEOUT — seconds for pg_isready check after promote (default: 30)

set -euo pipefail

REPMGR_CONF="${REPMGR_CONF:-/etc/repmgr.conf}"
REPMGR_USER="${REPMGR_USER:-repmgr}"
PG_ISREADY_TIMEOUT="${PG_ISREADY_TIMEOUT:-30}"

log() { echo "[$(date -u +%FT%TZ)] $*"; }

# ── preflight ──────────────────────────────────────────────────────────────────
if ! command -v repmgr &>/dev/null; then
  log "PREFLIGHT FAILED: repmgr binary not found in PATH"
  exit 2
fi

if [[ ! -f "${REPMGR_CONF}" ]]; then
  log "PREFLIGHT FAILED: ${REPMGR_CONF} not found"
  exit 2
fi

# Must be running as a standby — verify we're not already primary
ROLE=$(su - "${REPMGR_USER}" -c "repmgr -f '${REPMGR_CONF}' node check --role" 2>/dev/null | grep -oP '(primary|standby)' | head -1 || true)
if [[ "${ROLE}" == "primary" ]]; then
  log "PREFLIGHT FAILED: this node is already the primary — promote is not needed"
  exit 2
fi

# ── promote ────────────────────────────────────────────────────────────────────
log "Promoting this standby to primary via repmgr..."
su - "${REPMGR_USER}" -c "repmgr -f '${REPMGR_CONF}' standby promote --siblings-follow --log-level INFO"

# ── verify ─────────────────────────────────────────────────────────────────────
log "Waiting up to ${PG_ISREADY_TIMEOUT}s for PostgreSQL to accept connections..."
DEADLINE=$(( $(date +%s) + PG_ISREADY_TIMEOUT ))
while true; do
  if (( $(date +%s) >= DEADLINE )); then
    log "FAILED: pg_isready not satisfied after ${PG_ISREADY_TIMEOUT}s post-promote"
    exit 1
  fi
  if pg_isready -U "${REPMGR_USER}" -q 2>/dev/null; then
    break
  fi
  sleep 2
done

ROLE_NOW=$(su - "${REPMGR_USER}" -c "repmgr -f '${REPMGR_CONF}' node check --role" 2>/dev/null | grep -oP '(primary|standby)' | head -1 || true)
if [[ "${ROLE_NOW}" != "primary" ]]; then
  log "FAILED: repmgr still shows role=${ROLE_NOW} after promote"
  exit 1
fi

log "OK: node promoted to primary and accepting connections."
exit 0
