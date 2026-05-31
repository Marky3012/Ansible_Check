# Extension Guide

How to add new capabilities to the framework without breaking existing behavior.

---

## 1. Add a new service to health checks

Example: add Suricata IDS monitoring.

**Step 1** — Create the check task file:
```
roles/wazuh_healthcheck/tasks/check_suricata.yml
```
Follow the pattern of existing check files: register a named fact (`suricata_status_entry`), set a `status` field (`UP`/`DOWN`/`SKIPPED`), never use `failed_when: true`.

**Step 2** — Add a feature flag to defaults:
```yaml
# roles/wazuh_healthcheck/defaults/main.yml
enable_suricata_check: false
```

**Step 3** — Include the task in `main.yml` with a guard:
```yaml
- name: Run Suricata health check
  ansible.builtin.include_tasks: check_suricata.yml
  when:
    - enable_suricata_check | bool
    - inventory_hostname in groups['suricata_nodes'] | default([])
```

**Step 4** — Add service-specific vars to the right `group_vars/` file (e.g., `inventory/group_vars/suricata_nodes.yml`).

**Step 5** — Add the component to `health_report.j2` under the existing table.

No other files need to change.

---

## 2. Add a new playbook / mode

Example: add an API key rotation playbook.

**Step 1** — Create `playbooks/rotate_api_keys.yml` following the thin-playbook pattern (just hosts + role reference).

**Step 2** — Create `roles/wazuh_rotate_api_keys/` with `tasks/main.yml` and `defaults/main.yml`.

**Step 3** — Register the new mode in `master.yml`:
```yaml
vars:
  valid_modes:
    - healthcheck
    - configure
    - troubleshoot
    - recovery
    - autonomous
    - agent_ops
    - rotate_api_keys   # ← add here
```

**Step 4** — Document the new mode in `README.md` under the Mode Reference table.

No other files need to change.

---

## 3. Add a new notification channel

Example: add PagerDuty.

**Step 1** — Create `roles/wazuh_recovery/tasks/notify_pagerduty.yml`:
```yaml
- name: "[NOTIFY] Send PagerDuty event"
  ansible.builtin.uri:
    url: "https://events.pagerduty.com/v2/enqueue"
    method: POST
    body_format: json
    body:
      routing_key: "{{ vault_pagerduty_routing_key }}"
      event_action: trigger
      payload:
        summary: "Recovery {{ recovery_op }} — {{ inventory_hostname }}"
        severity: critical
    status_code: 202
  delegate_to: localhost
  run_once: true
```

**Step 2** — Add the dispatch condition to `roles/wazuh_recovery/tasks/notify.yml`:
```yaml
- name: "[NOTIFY] Send PagerDuty notification"
  ansible.builtin.include_tasks: notify_pagerduty.yml
  when: notification_target == 'pagerduty'
```

**Step 3** — Add `vault_pagerduty_routing_key` to `vars/vault.yml.example`.

**Step 4** — Set `notification_target: pagerduty` in `inventory/group_vars/all.yml`.

No other files need to change.
