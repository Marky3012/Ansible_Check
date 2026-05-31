module.exports = {
  apps: [{
    name        : 'vip-failback-watcher',
    script      : './failback-watcher.js',
    cwd         : '/opt/vip-failback',
    autorestart : true,
    restart_delay: 5000,
    max_restarts : 10,
    watch        : false,
    log_date_format: 'YYYY-MM-DD HH:mm:ss',
    out_file     : '/var/log/vip-failback.log',
    error_file   : '/var/log/vip-failback-err.log',
    merge_logs   : true,
    env: { NODE_ENV: 'production' }
  }]
};
