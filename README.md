# Ansible_Check

Autonomous Ansible framework for operating a Wazuh SIEM deployment with HAProxy + Keepalived HA infrastructure.

---

## Deployment Topology

```
  Wazuh Agents (port 1514)
         │
         ▼
  VIP: 172.21.1.120 / enp1s0   ← VRRP VI_DC (router_id 51)
         │
  ┌──────┴──────┐
  │             │
172.21.1.93   172.21.1.94
HAProxy        HAProxy
Keepalived     Keepalived
MASTER(150)    BACKUP(140)
  │             │
  └──────┬──────┘
         │ leastconn / tcp-check
  ┌──────┼──────┬──────┐
  │      │      │      │
mgr1   mgr2   mgr3   mgr4
.1.85  .1.86  .5.85  .5.86
       :1514 each
```

**Versions:** HAProxy 2.8.16 · Keepalived 2.2.8 · Wazuh 4.11.2 · Ubuntu 24.04

---

## Repository Structure

```
.
├── ref/                        # Live configs captured from production nodes
│   ├── haproxy-keepalived-*/   # MASTER node (172.21.1.93) snapshot
│   ├── haproxy-keepalived-worker-*/  # BACKUP node (172.21.1.94) snapshot
│   └── vip-failback/           # DR failback watcher (Node.js/PM2)
│
├── wazuh-ops/                  # Ansible framework (primary working directory)
│   ├── master.yml              # Single entrypoint — always use this
│   ├── ansible.cfg
│   ├── inventory/
│   │   ├── hosts.yml
│   │   └── group_vars/
│   ├── playbooks/              # One file per mode
│   ├── roles/                  # wazuh_healthcheck, configure, troubleshoot, recovery, autonomous
│   ├── scripts/wrappers/       # Wrap existing failover/failback scripts — never replace them
│   └── vars/vault.yml.example  # Copy to vault.yml, fill, then ansible-vault encrypt
│
├── roles/                      # Shared role stubs (agent, common, indexer, manager)
├── scripts/wrappers/           # Additional wrappers (indexer, manager, postgres ops)
├── inventory/                  # Legacy/alternate inventory
└── CLAUDE.md                   # AI assistant guidance for this repo
```

---

## Quick Start

```bash
cd wazuh-ops/

# 1. Install collections (if any added to requirements.yml later)
ansible-galaxy collection install -r requirements.yml

# 2. Set up vault
cp vars/vault.yml.example vars/vault.yml
# Fill in all CHANGE_ME values, then:
ansible-vault encrypt vars/vault.yml

# 3. Test connectivity
ansible all -m ping --ask-vault-pass

# 4. Run a health check (read-only, safe anytime)
ansible-playbook master.yml -e "mode=healthcheck" --ask-vault-pass
```

---

## Modes

| Command | What it does | Mutates state? |
|---------|-------------|---------------|
| `mode=healthcheck` | Checks all components, writes JSON + text report to `reports/` | No |
| `mode=configure` | Pushes HAProxy/Keepalived/Manager configs, validates before reload | Yes |
| `mode=troubleshoot` | Collects logs, checks ports, detects config drift, bundles artifact | No |
| `mode=recovery op=failover` | PREFLIGHT → failover → VALIDATE → REPORT | Yes |
| `mode=recovery op=failback` | PREFLIGHT → failback → VALIDATE → REPORT | Yes |
| `mode=autonomous` | Evaluates health, auto-triggers configure/recovery/escalation | Conditional |
| `mode=agent_ops` | Re-enrolls disconnected agents via Manager API | Yes |

```bash
# Syntax check (always run before a production change)
ansible-playbook master.yml --syntax-check -e "mode=healthcheck"

# Dry run
ansible-playbook master.yml --check -e "mode=configure"

# Target a single node group
ansible-playbook master.yml -e "mode=healthcheck" --limit haproxy_nodes

# Selective tag
ansible-playbook master.yml -e "mode=configure" --tags configure_haproxy
```

---

## Vault Keys Required

All secrets live in `wazuh-ops/vars/vault.yml` (Ansible Vault encrypted). See `vault.yml.example` for the full list:

```
vault_wazuh_api_user / vault_wazuh_api_password
vault_wazuh_indexer_user / vault_wazuh_indexer_password
vault_haproxy_stats_user / vault_haproxy_stats_password
vault_keepalived_auth_pass
vault_notification_webhook
vault_wazuh_agent_enrollment_password
vault_wazuh_cluster_key
```

---

## Recovery Sequence

Recovery always runs in strict order — each stage is a hard abort gate:

```
PREFLIGHT → INVOKE → VALIDATE → REPORT
```

If any gate fails, `escalate.yml` runs and the play aborts. Recovery is never triggered outside this sequence.

---

## ref/ Directory

The `ref/` directory contains point-in-time snapshots of the live HAProxy and Keepalived configurations collected from both HA nodes on 2026-05-11. All IPs, ports, interface names, VRRP parameters, and backend server lists in `group_vars/` and Jinja2 templates are derived from these files. Do not delete them.

---

## Extending the Framework

| Task | Steps |
|------|-------|
| Add a service to health checks | Create `check_<svc>.yml`, add `enable_<svc>_check: false` to defaults, include with `when:` guard |
| Add a new mode | Create `playbooks/<name>.yml`, register mode in `master.yml`, create role |
| Add a notification channel | Create `notify_<channel>.yml` in `wazuh_recovery/tasks/`, dispatch from `notify.yml` |

See `wazuh-ops/extensions/README.md` for detailed step-by-step guides.
