#!/usr/bin/env bash
# failover_wrapper.sh
# Thin wrapper around the site-specific failover script.
# Normalizes exit codes so Ansible tasks get a reliable rc.
#
# Usage: This script is copied to /opt/wazuh-ops/ on the target node
#        by roles/wazuh_recovery/tasks/invoke_failover.yml and executed there.
#
# To integrate your real failover logic, drop your script at:
#   /opt/wazuh-ops/failover.sh
# and ensure it is executable (chmod 750).

set -euo pipefail

REAL_SCRIPT="/opt/wazuh-ops/failover.sh"
LOG_TAG="wazuh-ops-failover"

log() { logger -t "$LOG_TAG" "$*" || echo "[$LOG_TAG] $*" >&2; }

if [[ ! -f "$REAL_SCRIPT" ]]; then
  log "ERROR: $REAL_SCRIPT not found. Drop your failover script there and retry."
  exit 127
fi

if [[ ! -x "$REAL_SCRIPT" ]]; then
  log "ERROR: $REAL_SCRIPT is not executable. Run: chmod 750 $REAL_SCRIPT"
  exit 126
fi

log "Invoking failover: $REAL_SCRIPT $*"
"$REAL_SCRIPT" "$@"
RC=$?

if [[ $RC -eq 0 ]]; then
  log "Failover completed successfully."
else
  log "Failover script exited with code $RC."
fi

exit $RC
