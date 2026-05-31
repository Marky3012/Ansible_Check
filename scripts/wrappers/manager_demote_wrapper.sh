#!/usr/bin/env bash
# manager_demote_wrapper.sh — run ON the node being demoted back to worker
# Used during manager failback: sets node_type=worker, restarts wazuh-manager.
# The Ansible play coordinates the master change separately.
#
# Exit codes: 0=success  1=runtime failure  2=preflight failure
# Required env vars:
#   OSSEC_CONF       — path to ossec.conf (default: /var/ossec/etc/ossec.conf)
#   MANAGER_SERVICE  — systemd unit name (default: wazuh-manager)
#   MANAGER_MASTER_IP — IP of the new master this worker should connect to
#   CLUSTER_KEY      — Wazuh cluster key
#   START_TIMEOUT    — seconds to wait for service ready (default: 60)

set -euo pipefail

OSSEC_CONF="${OSSEC_CONF:-/var/ossec/etc/ossec.conf}"
MANAGER_SERVICE="${MANAGER_SERVICE:-wazuh-manager}"
MANAGER_MASTER_IP="${MANAGER_MASTER_IP:?MANAGER_MASTER_IP env var is required}"
CLUSTER_KEY="${CLUSTER_KEY:?CLUSTER_KEY env var is required}"
START_TIMEOUT="${START_TIMEOUT:-60}"

log() { echo "[$(date -u +%FT%TZ)] $*"; }

if [[ ! -f "${OSSEC_CONF}" ]]; then
  log "PREFLIGHT FAILED: ${OSSEC_CONF} not found"
  exit 2
fi

if ! command -v python3 &>/dev/null; then
  log "PREFLIGHT FAILED: python3 not found"
  exit 2
fi

BACKUP="${OSSEC_CONF}.pre-demote.$(date +%s)"
cp "${OSSEC_CONF}" "${BACKUP}"
log "Backed up ossec.conf to ${BACKUP}"

python3 - <<PYEOF
import re

conf_path = '${OSSEC_CONF}'
master_ip = '${MANAGER_MASTER_IP}'
cluster_key = '${CLUSTER_KEY}'

with open(conf_path, 'r') as f:
    content = f.read()

# Set node_type to worker
content, n = re.subn(
    r'(<node_type>\s*)master(\s*</node_type>)',
    r'\1worker\2',
    content
)
if n == 0:
    if '<node_type>' not in content:
        content = content.replace('</cluster>', '  <node_type>worker</node_type>\n</cluster>')
    else:
        print("INFO: node_type already worker — no change needed")

# Point <nodes> list at the new master
content = re.sub(
    r'<nodes>.*?</nodes>',
    '<nodes><node>' + master_ip + '</node></nodes>',
    content,
    flags=re.DOTALL
)

# Patch cluster key
content = re.sub(
    r'(<key>)[^<]*(</key>)',
    r'\g<1>' + cluster_key + r'\g<2>',
    content,
    count=1
)

with open(conf_path, 'w') as f:
    f.write(content)

print("OK: ossec.conf patched — node_type=worker, master=" + master_ip)
PYEOF

log "Restarting ${MANAGER_SERVICE} as worker..."
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

log "OK: ${MANAGER_SERVICE} active as worker."
exit 0
