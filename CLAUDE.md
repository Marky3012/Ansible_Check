# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Mission

This is a **production-grade, autonomous Ansible framework** for operating a Wazuh SIEM deployment with HA infrastructure (HAProxy + Keepalived). The framework is modular, extensible, idempotent, and self-healing.

## Before Writing Any Code — Read `./ref/`

**Always read every file in `./ref/` first.** That directory contains live HAProxy and Keepalived configs for this deployment. Parse and derive:
- HAProxy: frontend/backend names, VIPs, server IPs, health check intervals, stats socket path, stats credentials
- Keepalived: VRRP instance names, interface names, virtual IPs, priorities (MASTER vs BACKUP), track_script blocks, notify scripts
- Any failover/failback shell scripts — understand trigger conditions, what they restart, and exit codes

**All inventory IPs, hostnames, ports, and interface names must be derived from `./ref/` — never hardcoded.** Everything becomes a Jinja2 variable in `group_vars/`.

## Common Commands

```bash
# Single entrypoint — always use master.yml with a mode
ansible-playbook master.yml -e "mode=healthcheck"
ansible-playbook master.yml -e "mode=configure"
ansible-playbook master.yml -e "mode=troubleshoot"
ansible-playbook master.yml -e "mode=recovery op=failover"
ansible-playbook master.yml -e "mode=autonomous"

# Syntax check before any run
ansible-playbook master.yml --syntax-check -e "mode=healthcheck"

# Dry run (never mutates)
ansible-playbook master.yml --check -e "mode=configure"

# Target specific hosts
ansible-playbook master.yml -e "mode=healthcheck" --limit haproxy_nodes

# Selective execution by tag
ansible-playbook master.yml -e "mode=configure" --tags configure_haproxy

# Encrypt a secret for vault.yml
ansible-vault encrypt_string 'secret' --name 'vault_wazuh_api_password'

# Test connectivity
ansible all -m ping
```

## Architecture

### Mode-Based Entrypoint

`master.yml` is the **only** entrypoint. It validates `mode` (fails fast if unknown), loads `vars/vault.yml`, prints a run header, then imports the matching playbook from `playbooks/`. Never run individual playbooks directly in production.

Valid modes: `healthcheck`, `configure`, `troubleshoot`, `recovery`, `autonomous`

### Role Responsibilities

| Role | Mutates State? | Purpose |
|------|---------------|---------|
| `wazuh_healthcheck` | No | Reads state; produces structured JSON + text reports |
| `wazuh_configure` | Yes | Pushes and validates config via templates |
| `wazuh_troubleshoot` | No | Collects logs, checks ports, detects config drift |
| `wazuh_recovery` | Yes | Orchestrates failover/failback with hard abort gates |
| `wazuh_autonomous` | Conditional | Evaluates health; triggers recovery or configure as needed |

### Recovery Sequence (Strict — Do Not Alter Order)

```
PREFLIGHT → INVOKE → VALIDATE → REPORT
```
Each stage is a hard abort gate. If any gate fails, `escalate.yml` runs and the play fails — never proceeds to the next stage. Do not restart services or trigger recovery outside this sequence.

### HAProxy + Keepalived Templates

`roles/wazuh_configure/templates/haproxy.cfg.j2` and `keepalived.conf.j2` are derived from `./ref/` configs. Every IP, port, interface, password, and hostname is a variable. The rendered output must be identical to the ref config when defaults are used. Always run `haproxy -c -f` validation before any HAProxy reload.

### Health Check Output Contract

Every check task registers a named variable (e.g., `wazuh_manager_status`, `haproxy_backend_states`) and accumulates into `health_summary`:
```yaml
{ component, status, detail, timestamp }
```
At role end, write:
- `reports/healthcheck_<timestamp>.json` (structured)
- `reports/healthcheck_<timestamp>.txt` (rendered from `health_report.j2`)

HAProxy checks must use the stats socket or HTTP stats endpoint — not `systemctl status`. Report per-backend server state (UP/DOWN/MAINT).

Keepalived checks must verify: process running, VRRP state matches expected role, VIP bound to correct interface on MASTER.

## Critical Constraints

- **Do not replace existing failover/failback scripts** — wrap them via `scripts/wrappers/failover_wrapper.sh`. The wrapper normalizes exit codes; the original scripts are never modified.
- **Health checks and troubleshoot are read-only** — no service restarts, no config writes.
- **Config validation before reload** — `haproxy -c -f` must pass before any HAProxy reload handler fires.
- **`serial: 1`** on all plays targeting production hosts unless explicitly overridden in the play.
- **FQCN for all modules** — `ansible.builtin.template`, not `template`. Ansible 2.14+ target.
- **No Python 2 compatibility shims** — Python 3 only.
- **No community collections assumed** — if a community module is needed, add it to `requirements.yml` and note it in README.

## Secrets

All secrets live in `vars/vault.yml` (Ansible Vault encrypted). Every secret is prefixed `vault_`. Reference the `vault_*` variable in tasks — never inline values. Required vault keys:

```
vault_wazuh_api_user, vault_wazuh_api_password
vault_wazuh_indexer_user, vault_wazuh_indexer_password
vault_haproxy_stats_user, vault_haproxy_stats_password
vault_notification_webhook
```

`vars/vault.yml.example` must exist with dummy values for every key in `vault.yml`.

## Extensibility Contract

### Add a new service to health checks
1. Create `roles/wazuh_healthcheck/tasks/check_<service>.yml`
2. Add `enable_<service>_check: false` to `roles/wazuh_healthcheck/defaults/main.yml`
3. Include the task in `main.yml` with `when: enable_<service>_check`
4. Add service vars to the appropriate `group_vars/` file
5. No other files change

### Add a new playbook/mode
1. Create `playbooks/<name>.yml`
2. Register it as a valid `mode` in `master.yml`
3. Create its role under `roles/` following the same structure
4. Document it in `README.md`

### Add a new notification channel
1. Create `roles/wazuh_recovery/tasks/notify_<channel>.yml`
2. `notify.yml` dispatches based on `notification_target` from `group_vars/all.yml`

## Quality Gates (Run Before Declaring Done)

- `ansible-playbook master.yml --syntax-check -e "mode=healthcheck"` passes
- All Jinja2 templates render without undefined variable errors when defaults are loaded
- `vars/vault.yml.example` has a key for every secret referenced in any task
- No task contains a hardcoded IP, password, hostname, or port
- Every role has a `defaults/main.yml` with all variables documented
- `reports/` is in `.gitignore`

## Reports Directory

`reports/` is auto-created at runtime and gitignored. All run artifacts (JSON + text reports) land here. The directory contains only a `.gitkeep` in source control.
