const http  = require('http');
const https = require('https');
const { execSync } = require('child_process');
const cfg   = require('./config');

let dcHealthyCount     = 0;
let failbackInProgress = false;

function log(msg) {
  console.log(`[${new Date().toISOString()}] ${msg}`);
}

function checkDC() {
  return new Promise((resolve) => {
    const mod = cfg.DC_CHECK_URL.startsWith('https') ? https : http;
    const req = mod.get(cfg.DC_CHECK_URL, { timeout: 5000 }, (res) => {
      resolve(res.statusCode >= 200 && res.statusCode < 500);
    });
    req.on('error',   () => resolve(false));
    req.on('timeout', () => { req.destroy(); resolve(false); });
  });
}

function runCmd(cmd) {
  if (cfg.DR_LOCAL) {
    log(`[LOCAL] ${cmd}`);
    execSync(cmd, { stdio: 'inherit' });
  } else {
    const ssh = `ssh -i ${cfg.DR_SSH_KEY} -o StrictHostKeyChecking=no -o ConnectTimeout=10 ${cfg.DR_SSH_USER}@${cfg.DR_VM_IP} "${cmd}"`;
    log(`[SSH → 192.168.3.163] ${cmd}`);
    execSync(ssh, { stdio: 'inherit' });
  }
}

async function doFailback() {
  failbackInProgress = true;

  log('╔══════════════════════════════════════════════════════╗');
  log('║  DC VIP 192.168.3.183 is healthy — starting failback ║');
  log('╚══════════════════════════════════════════════════════╝');

  try {
    // ── Step 1: Drop DR VIP (192.168.3.185) by stopping keepalived on DR VM ──
    log('► Step 1: Stopping keepalived on DR VM 192.168.3.163...');
    log('         DR VIP 192.168.3.185 will disappear from network');
    runCmd('systemctl stop keepalived');
    log('✔ keepalived stopped on DR');

    // ── Step 2: Wait 5 min — agents lose 192.168.3.185, reconnect to 192.168.3.183 ──
    log(`► Step 2: Waiting ${cfg.DR_KEEPALIVED_STOP_DURATION_SEC}s (5 min)...`);
    log('         Agents will detect DR VIP 192.168.3.185 is down');
    log('         Agents will auto-reconnect to DC VIP 192.168.3.183');
    await new Promise(r => setTimeout(r, cfg.DR_KEEPALIVED_STOP_DURATION_SEC * 1000));

    // ── Step 3: Bring DR keepalived back as BACKUP (no VIP conflict) ──
    log('► Step 3: Restarting keepalived on DR VM 192.168.3.163 as BACKUP...');
    runCmd('systemctl start keepalived');
    log('✔ DR keepalived restarted in BACKUP state');
    log('         DC VIP 192.168.3.183 = MASTER ✅');
    log('         DR VIP 192.168.3.185 = BACKUP (standby, no conflict) ✅');

    log('╔══════════════════════════════════╗');
    log('║  Failback complete               ║');
    log('║  Active VIP : 192.168.3.183 (DC) ║');
    log('║  Standby VIP: 192.168.3.185 (DR) ║');
    log('╚══════════════════════════════════╝');

  } catch (err) {
    log(`✘ ERROR during failback: ${err.message}`);
    log('  Attempting to restore DR keepalived...');
    try {
      runCmd('systemctl start keepalived');
      log('✔ DR keepalived restored after error');
    } catch (e2) {
      log(`✘ Could not restore DR keepalived: ${e2.message}`);
    }
  }

  // Cooldown — 60s before next failback can trigger
  setTimeout(() => {
    failbackInProgress = false;
    dcHealthyCount     = 0;
    log('► Cooldown complete. Resuming health checks on 192.168.3.183');
  }, 60000);
}

async function tick() {
  if (failbackInProgress) return;

  const healthy = await checkDC();

  if (healthy) {
    dcHealthyCount++;
    log(`✔ DC VIP 192.168.3.183 healthy [${dcHealthyCount}/${cfg.DC_HEALTHY_THRESHOLD}]`);
    if (dcHealthyCount >= cfg.DC_HEALTHY_THRESHOLD) {
      await doFailback();
    }
  } else {
    if (dcHealthyCount > 0) {
      log('✘ DC VIP 192.168.3.183 unhealthy — resetting healthy counter');
    } else {
      log('✘ DC VIP 192.168.3.183 unreachable — DR VIP 192.168.3.185 remains active');
    }
    dcHealthyCount = 0;
  }
}

log('═══════════════════════════════════════════════════════');
log('  VIP Failback Watcher started');
log('  Monitoring  : 192.168.3.183 (DC VIP)');
log('  DR VM       : 192.168.3.163');
log('  DR VIP      : 192.168.3.185');
log('  Check every : 15s  |  Threshold: 3  |  Stop: 5 min');
log('═══════════════════════════════════════════════════════');

setInterval(tick, cfg.DC_CHECK_INTERVAL_MS);
tick();
