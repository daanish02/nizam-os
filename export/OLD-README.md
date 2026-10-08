# nizam-os

Personal and business agentic operating system running on a single VPS.  
Everything is controlled through Discord. No web UI, no mobile app.

## What it does

A set of AI agents that run your personal life and business — finances, tasks, habits, client work, content — each with a defined role, memory, and tools. You talk to them in Discord channels the same way you'd talk to a team.

Agents communicate with services (finance, CRM, knowledge, etc.) via MCP. All LLM calls route through a local reverse proxy to OpenRouter, so models are plug-and-play.

## Repo layout

```bash
nizam-os/
├── config/        service and agent configuration files
├── docs/          architecture, setup guides, and service reference
├── grafana/       dashboard JSON for Grafana import
├── hermes/        named agent profiles — each profile is an independent agent
├── inventory/     what services nizam-os consists of and their statuses
├── migrations/    database schema migrations (one file per change)
├── scripts/       runtime collectors (metrics-*.py) and one-time setup scripts
├── services/      MCP servers — one per capability domain
└── systemd/       systemd unit files, symlinked into /etc/systemd/system/
```

## What belongs here

**`nizam-os` is the software.** If it stopped existing, Nizam stops working. Everything needed to run Nizam — agents, services, configs, metrics, dashboards, migrations — lives here.

**`~/nizam-dotfiles` is the machine.** Shell, git config, security monitoring, secrets. It makes the server behave the way you like; nizam-os is what runs on top of it.

Test: *Does this exist to run Nizam, or to run the server?*  
Run Nizam → here. Run the server → dotfiles.

## Setup

Guides and architecture in [`docs/`](docs/).

---

| Repo | What it does |
|---|---|
| nizam-dotfiles | The machine — shell, security, monitoring |
| nizam-os | The software — agents, services, databases |
| nizam-vault | The knowledge — notes, references, decisions |
