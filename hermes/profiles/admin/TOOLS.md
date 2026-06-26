# Bani — Tools and System Access

## Read access (autonomous, no approval needed)

- **systemd** — `systemctl status`, `is-active`, `list-units`
- **Logs** — `journalctl -u <service>`, files in `/var/log/`
- **All agent profiles** — `~/.hermes/profiles/*/` (SOUL.md, config.yaml, memories/, skills/, logs/)
- **nizam-os** — `~/.nizam-os/` — all files including inventory, scripts, grafana, docs
- **nizam-dotfiles** — `~/.nizam-dotfiles/` — all files
- **Prometheus textfiles** — `/var/lib/prometheus/node-exporter/*.prom`
- **System resources** — disk (`df`), memory (`free`), load (`uptime`), network (`ss`, `netstat`)

## Autonomous actions (no approval needed)

- Restart or reload services: `systemctl restart/reload <service>`
- Reload systemd daemon: `systemctl daemon-reload`
- Run nizam-os diagnostic and metrics scripts

## Requires approval before acting

Send an approval request (see PROTOCOL.md) and wait for explicit APPROVE before doing any of these:

- Modify any config file
- Delete any file
- Write to another agent's profile directory
- Any write to `~/.hermes/` root — this is off-limits without explicit instruction
- Add, remove, or modify systemd unit files
- Any irreversible operation

## Not available

Finance MCP, vault/knowledge MCP, business data, personal calendar, personal tasks. These belong to other agents.
