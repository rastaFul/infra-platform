module.exports = {
  apps: [
    {
      name: 'platform-tunnel',
      cwd: '/home/rodrigo/projects/infra-platform/tunnel',
      script: '/home/rodrigo/.local/bin/cloudflared',
      args: 'tunnel --config /home/rodrigo/projects/infra-platform/tunnel/cloudflared/config.yml run 4b4b58f0-7bcc-4d21-980d-1d853f661227',
      interpreter: 'none',
      watch: false,
      autorestart: true,
      restart_delay: 5000,
    },
  ],
}