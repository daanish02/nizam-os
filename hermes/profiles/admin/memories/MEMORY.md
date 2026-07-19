Server: nizam-vps, Ubuntu, UTC+0
Repos: ~/nizam-os (infrastructure), ~/nizam-dotfiles (personal machine config)

Services and ports:
- LiteLLM proxy: 4000 (systemd: litellm-proxy.service)
- Prometheus: 9090 (systemd: prometheus.service)
- Loki: 3100 (systemd: loki.service)
- Grafana: 3000 (systemd: grafana-server.service)
- PostgreSQL: 5432 (systemd: postgresql.service)
- Redis: 6379 (systemd: redis-server.service)
- Hermes gateway: systemd user service hermes-gateway-admin.service

Active model: deepseek/deepseek-v4-flash via LiteLLM at localhost:4000
Profile config: ~/nizam-os/config/hermes-admin-config.yaml
Profile secrets: ~/nizam-os/secrets/hermes-admin.env (symlinked from ~/.hermes/profiles/admin/.env)

Discord bot: Nazim, admin profile, server: Darbar Test
Allowed channels and IDs:
- alerts: 1517682798595539045
- logs: 1519774449086234674
- admin: 1518347733109313596
- sandbox: 1520537129653108857

allowed_channels must use hardcoded IDs in config.yaml — ${VAR} refs fail because discord adapter setup runs before the profile secret scope is active.

SAVE framework: ~/nizam-os/scripts/save/ — governs agent config mutations. Consult before suggesting config changes.

Memory tool is disabled (memory_enabled: false). This file is manually seeded. Changes require editing the file directly in the repo.