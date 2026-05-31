#!/usr/bin/env bash
# failback_wrapper.sh
# Thin wrapper around the site-specific failback script.
# Normalizes exit codes so Ansible tasks get a reliable rc.
#
# Usage: This script is copied to /opt/wazuh-ops/ on the target node
#        by roles/wazuh_recovery/tasks/invoke_failback.yml and executed there.
#
# To integrate your real failback logic, drop your script at:
#   /opt/wazuh-ops/failback.sh
# and ensure it is executable (chmod 750).

set -euo pipefail

REAL_SCRIPT="/opt/wazuh-ops/failback.sh"
LOG_TAG="wazuh-ops-failback"

log() { logger -t "$LOG_TAG" "$*" || echo "[$LOG_TAG] $*" >&2; }

if [[ ! -f "$REAL_SCRIPT" ]]; then
  log "ERROR: $REAL_SCRIPT not found. Drop your failback script there and retry."
  exit 127
fi

if [[ ! -x "$REAL_SCRIPT" ]]; then
  log "ERROR: $REAL_SCRIPT is not executable. Run: chmod 750 $REAL_SCRIPT"
  exit 126
fi

log "Invoking failback: $REAL_SCRIPT $*"
"$REAL_SCRIPT" "$@"
RC=$?

if [[ $RC -eq 0 ]]; then
  log "Failback completed successfully."
else
  log "Failback script exited with code $RC."
fi

exit $RC
