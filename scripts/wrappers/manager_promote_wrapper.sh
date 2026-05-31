#!/usr/bin/env bash
# manager_promote_wrapper.sh — run ON the worker node being promoted to master
# Edits ossec.conf to set node_type=master, then restarts wazuh-manager.
# The Ansible play MUST fence (stop + verify) the old master BEFORE calling this.
#
# Exit codes: 0=success  1=runtime failure  2=preflight failure
# Required env vars:
#   OSSEC_CONF       — path to ossec.conf (default: /var/ossec/etc/ossec.conf)
#   MANAGER_SERVICE  — systemd unit name (default: wazuh-manager)
#   CLUSTER_KEY      — Wazuh cluster key (must match existing cluster)
#   START_TIMEOUT    — seconds to wait for service ready (default: 60)

set -euo pipefail

OSSEC_CONF="${OSSEC_CONF:-/var/ossec/etc/ossec.conf}"
MANAGER_SERVICE="${MANAGER_SERVICE:-wazuh-manager}"
CLUSTER_KEY="${CLUSTER_KEY:?CLUSTER_KEY env var is required}"
START_TIMEOUT="${START_TIMEOUT:-60}"

log() { echo "[$(date -u +%FT%TZ)] $*"; }

# ── preflight ──────────────────────────────────────────────────────────────────
if [[ ! -f "${OSSEC_CONF}" ]]; then
  log "PREFLIGHT FAILED: ${OSSEC_CONF} not found"
  exit 2
fi

if ! command -v python3 &>/dev/null; then
  log "PREFLIGHT FAILED: python3 not found"
  exit 2
fi

# ── backup conf ────────────────────────────────────────────────────────────────
BACKUP="${OSSEC_CONF}.pre-promote.$(date +%s)"
cp "${OSSEC_CONF}" "${BACKUP}"
log "Backed up ossec.conf to ${BACKUP}"

# ── patch node_type and cluster key ───────────────────────────────────────────
python3 - <<PYEOF
import re, sys

conf_path = '${OSSEC_CONF}'
cluster_key = '${CLUSTER_KEY}'

with open(conf_path, 'r') as f:
    content = f.read()

# Promote node_type
content, n = re.subn(
    r'(<node_type>\s*)worker(\s*</node_type>)',
    r'\1master\2',
    content
)
if n == 0:
    # Already master or tag missing — ensure it exists
    if '<node_type>' not in content:
        content = content.replace('</cluster>', '  <node_type>master</node_type>\n</cluster>')
        print("INFO: inserted missing node_type tag")
    else:
        print("INFO: node_type already set to master — no change needed")

# Patch cluster key
content = re.sub(
    r'(<key>)[^<]*(</key>)',
    r'\g<1>' + cluster_key + r'\g<2>',
    content,
    count=1
)

with open(conf_path, 'w') as f:
    f.write(content)

print("OK: ossec.conf patched — node_type=master")
PYEOF

# ── restart manager ────────────────────────────────────────────────────────────
log "Restarting ${MANAGER_SERVICE}..."
systemctl restart "${MANAGER_SERVICE}"

DEADLINE=$(( $(date +%s) + START_TIMEOUT ))
while true; do
  if (( $(date +%s) >= DEADLINE )); then
    log "FAILED: ${MANAGER_SERVICE} did not become active within ${START_TIMEOUT}s"
    exit 1
  fi
  if systemctl is-active --quiet "${MANAGER_SERVICE}"; then
    break
  fi
  sleep 3
done

log "OK: ${MANAGER_SERVICE} active as master."
exit 0
