module.exports = {
  // DC Primary health check (DC VM: 192.168.3.194, DC VIP: 192.168.3.183)
  DC_VM_IP: '192.168.3.194',
  DC_VIP: '192.168.3.183',
  DC_CHECK_URL: 'http://192.168.3.183',        // health check hits DC VIP directly
  DC_CHECK_INTERVAL_MS: 15000,                  // check every 15s
  DC_HEALTHY_THRESHOLD: 3,                      // 3 consecutive passes before failback

  // DR suppression duration
  DR_KEEPALIVED_STOP_DURATION_SEC: 300,         // 5 minutes

  // DR server (DR VM: 192.168.3.163, DR VIP: 192.168.3.185)
  DR_VM_IP: '192.168.3.163',
  DR_VIP: '192.168.3.185',
  DR_SSH_USER: 'root',
  DR_SSH_KEY: '/root/.ssh/id_rsa',

  // Set true if this script runs directly ON 192.168.3.163 (DR VM) — no SSH needed
  DR_LOCAL: false,
};
