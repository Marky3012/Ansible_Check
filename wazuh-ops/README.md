# wazuh-ops

Autonomous Ansible framework for operating a SIEM deployment with HA infrastructure (HAProxy + Keepalived).

---

## Architecture

```
                  ┌────────────────────────────────┐
  Agents ────────►  VIP (floating)                 │
  port 1514        172.21.1.120 / enp1s0           │
                  └──────────┬─────────────────────┘
                             │ VRRP VI_DC (router_id 51)
               ┌─────────────┴──────────────┐
         MASTER │                            │ BACKUP
      172.21.1.93                       172.21.1.94
      HAProxy + Keepalived              HAProxy + Keepalived
      priority 150                      priority 140
               └─────────────┬──────────────┘
                             │ leastconn / tcp-check
        ┌────────────────────┼────────────────────┐
        │                    │                    │
   mgr1:1514            mgr2:1514            mgr3/mgr4:1514
   172.21.1.85          172.21.1.86       172.21.5.85/86
        │                    │                    │
        └────────── Manager Cluster ──────────────┘
                         (Indexer nodes separate — see wazuh_indexers group)

  Control node (localhost)
    └── master.yml  ──► mode router  ──► playbooks/*.yml  ──► roles/
```

> Cluster size is fully data-driven. Add or remove nodes in `inventory/hosts.yml` — no templates or tasks change.

---

## Quick Start

```bash
# 1. Clone and enter the framework
cd wazuh-ops/

# 2. Install dependencies (if any community collections added later)
ansible-galaxy collection install -r requirements.yml

# 3. Set up secrets
cp vars/vault.yml.example vars/vault.yml
# Edit vars/vault.yml with real credentials, then:
ansible-vault encrypt vars/vault.yml

# 4. Update inventory with your real host IPs
vim inventory/hosts.yml

# 5. Test connectivity
ansible all -m ping --ask-vault-pass

# 6. Run your first health check
ansible-playbook master.yml -e "mode=healthcheck" --ask-vault-pass
```

---

## Mode Reference

| Mode | What it does | Mutates state? | Roles triggered | Safe in prod? |
|------|-------------|---------------|-----------------|---------------|
| `healthcheck` | Checks all components, writes JSON + text report | No | `wazuh_healthcheck` | Yes |
| `configure` | Pushes configs with pre-validation, reloads services | Yes | `wazuh_configure` | Yes (serial: 1) |
| `troubleshoot` | Collects logs, checks ports, detects drift, bundles artifact | No | `wazuh_troubleshoot` | Yes |
| `recovery op=failover` | PREFLIGHT → failover script → VALIDATE → REPORT | Yes | `wazuh_recovery` | Confirm first |
| `recovery op=failback` | PREFLIGHT → failback script → VALIDATE → REPORT | Yes | `wazuh_recovery` | Confirm first |
| `autonomous` | Evaluates health and auto-triggers configure/recovery/escalation | Conditional | `wazuh_autonomous` | Designed for cron |
| `agent_ops` | Re-enrolls disconnected agents via Manager API | Yes (restarts agent svc) | inline tasks | Yes |

---

## Variable Reference (`group_vars/all.yml`)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `wazuh_version` | string | `4.11.2` | Target Wazuh version |
| `wazuh_agent_port` | int | `1514` | Agent ↔ Manager TCP port |
| `wazuh_enrollment_port` | int | `1515` | Agent enrollment port |
| `wazuh_cluster_port` | int | `1516` | Manager cluster daemon port |
| `wazuh_api_port` | int | `55000` | Manager REST API port |
| `wazuh_indexer_port` | int | `9200` | OpenSearch HTTP port |
| `wazuh_dir` | path | `/var/ossec` | OSSEC base directory |
| `report_dir` | path | `../reports` | Control-node report output directory |
| `notification_target` | string | `log` | Notification channel: `slack` or `log` |
| `valid_modes` | list | see file | Valid values for `-e mode=` |

For `haproxy_nodes.yml`, `wazuh_managers.yml`, and `wazuh_indexers.yml` variable references, see the comments inside each file — every variable is documented inline.

---

## Vault Setup

```bash
# Create vault from example
cp vars/vault.yml.example vars/vault.yml

# Edit — fill in real values for all CHANGE_ME placeholders
vim vars/vault.yml

# Encrypt
ansible-vault encrypt vars/vault.yml

# Run playbooks with vault password
ansible-playbook master.yml -e "mode=healthcheck" --ask-vault-pass

# Or use a password file (gitignored)
echo "your-vault-password" > .vault_pass
chmod 600 .vault_pass
ansible-playbook master.yml -e "mode=healthcheck" --vault-password-file .vault_pass
```

Required vault keys (see `vars/vault.yml.example` for full list):
- `vault_wazuh_api_user` / `vault_wazuh_api_password`
- `vault_wazuh_indexer_user` / `vault_wazuh_indexer_password`
- `vault_haproxy_stats_user` / `vault_haproxy_stats_password`
- `vault_keepalived_auth_pass`
- `vault_notification_webhook`
- `vault_wazuh_agent_enrollment_password`
- `vault_wazuh_cluster_key`

---

## Integrating Failover/Failback Scripts

The `wazuh_recovery` role wraps — never replaces — your existing scripts.

1. Place your failover script at `/opt/wazuh-ops/failover.sh` on each HA node
2. Place your failback script at `/opt/wazuh-ops/failback.sh` on each HA node
3. Ensure both are executable: `chmod 750 /opt/wazuh-ops/failover.sh`

The framework copies `scripts/wrappers/failover_wrapper.sh` to the target and calls it. The wrapper validates the real script exists, logs to syslog, and passes exit codes through faithfully. A non-zero exit code from your script aborts the play at the INVOKE gate.

---

## Extending the Framework

See `extensions/README.md` for step-by-step guides to:
- Add a new service to health checks (e.g., Suricata, Zeek, Shuffle SOAR)
- Add a new playbook and mode
- Add a new notification channel

---

## Troubleshooting the Framework

**`mode is required` error**
Pass `-e "mode=healthcheck"` — the mode must always be explicit.

**`vault.yml` decrypt error**
Run with `--ask-vault-pass` or create `.vault_pass` (see Vault Setup above).

**HAProxy stats socket unavailable (`SOCKET_ERROR`)**
The stats socket is added to `haproxy.cfg` by the `wazuh_configure` role. Run `mode=configure` first if deploying to a fresh node, or check that `/var/run/haproxy/` exists and HAProxy has write permission.

**Keepalived state shows `SPLIT_BRAIN`**
Both nodes believe they are MASTER. Check network connectivity between HA nodes on the VRRP interface (`enp1s0`). Verify `keepalived_virtual_router_id` and `keepalived_auth_pass` match on all nodes.

**Recovery aborts at PREFLIGHT**
Read the preflight failure message — it names the exact assertion that failed. Common causes: standby HAProxy not running, Keepalived stopped, network partition.

**`autonomous` mode escalates immediately**
Check `roles/wazuh_autonomous/defaults/main.yml` thresholds. If `auto_recovery_enabled: false`, the role reports but never acts. Check the escalation report in `reports/`.
