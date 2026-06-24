# nizam-os

Personal and business agentic operating system running on a single VPS.  
Everything is controlled through Discord. No web UI, no mobile app.

## What it is

A set of AI agents that run your personal life and business — finances, tasks, habits, client work, content — each with a defined role, memory, and tools. You talk to them in Discord channels the same way you'd talk to a team.

Agents communicate with services (finance, CRM, knowledge, etc.) via MCP. All LLM calls route through a local reverse proxy to OpenRouter, so models are plug-and-play.

## Stack

- **VPS** — Hostinger, Ubuntu 24.04, 8GB RAM, 100GB SSD
- **Agents** — Hermes (Nous Research)
- **LLM routing** — LiteLLM → OpenRouter (any model, one config change)
- **Data** — PostgreSQL (all service data) + Redis (caching)
- **Observability** — Prometheus + Grafana (metrics ship with every step)
- **Interface** — Discord only

## Repo Layout

```bash
nizam-os/
├── config/               service configs (litellm.yaml, hermes config.yaml)
├── docs/                 setup guides and architecture
├── grafana/              Grafana dashboard JSON and provisioning files
├── hermes/               Hermes profiles (SOUL.md, skills, memory)
├── inventory/            tracked-services.txt — what nizam-os consists of
├── migrations/           dbmate SQL — one file per schema change
├── scripts/
│      ├── metrics-*.py   runtime collectors, fire every 60s via systemd timer
│      └── setup/         one-time install scripts (run once on fresh VPS)
├── services/             MCP servers — each a uv workspace member
└──systemd/               unit files, symlinked into /etc/systemd/system/
```

## What belongs here

**`nizam-os` is the software.** If it stopped existing, Nizam stops working. Everything needed to run Nizam — agents, services, configs, metrics, dashboards, migrations — lives here.

**`~/.nizam-dotfiles` is the machine.** Shell, git config, security monitoring, secrets. It makes the server behave the way you like; nizam-os is what runs on top of it.

Test: *Does this exist to run Nizam, or to run the server?*
Run Nizam → here. Run the server → dotfiles.

## Docs

Setup guides and architecture live in [`docs/`](docs/).
