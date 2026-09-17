module.exports = {
  apps: [
    {
      name: 'samafox-api',
      script: 'dist/index.js',
      cwd: '/home/ubuntu/apps/SamaFox/backend',
      instances: 1,
      exec_mode: 'fork',
      env_file: '.env',
      env: {
        NODE_ENV: 'production',
        PORT: 3000
      },
      error_file: './logs/error.log',
      out_file: './logs/output.log',
      merge_logs: true,
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      autorestart: true,
      watch: false,
      // 500M was a kill switch on the whole service. This is the ONLY process
      // (fork mode, one instance, room state in memory, no Redis adapter), so a
      // PM2 restart drops every socket at once and wipes every room — for
      // everyone, on every phone, at the same moment. Node with Prisma and a
      // few hundred sockets normally sits at 200-350M and GROWS between
      // collections, so 500M was reachable in ordinary use.
      //
      // Two changes, in the right order: V8 is told to collect at 768M of heap,
      // so it garbage-collects instead of growing; and PM2's blunt restart is
      // moved above that, as a last resort for a real leak rather than a
      // reaction to normal growth. Keeps >900M for the OS, Postgres and coturn
      // on a 2G box.
      node_args: ['--max-old-space-size=768'],
      max_memory_restart: '1024M',
      // Never hot-loop a crashing process: 100ms, 200ms, ... up to 15s.
      exp_backoff_restart_delay: 100
    }
  ]
};
