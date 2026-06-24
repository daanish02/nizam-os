# Nizam-OS — Setup Guide

Agentic OS on a single Hostinger VPS (Ubuntu 24.04, 8GB RAM, 100GB SSD).  
Sole interface: Discord. Framework: Hermes Agent. LLM routing: OpenRouter via LiteLLM.

Architecture: [architecture.md](architecture.md) · Agents: [agents.md](agents.md) · Services: [services.md](services.md)

---

## Stack Overview

```
Discord
  └── Hermes Gateway (agents)
        └── LiteLLM Proxy :4000
              └── OpenRouter → any model
                    └── PostgreSQL (spend logs, all service data)
                    └── Redis (response cache, tool result cache)

Prometheus ← node-exporter ← textfile collectors (metrics-*.py / metrics-*.sh)
Grafana ← Prometheus
```

---

## Steps

| # | What | Status | Guide |
|---|---|---|---|
| 1 | LLM observability — LiteLLM proxy + spend logs + metrics + Grafana | ✅ Done | [step-1-llm-observability.md](step-1-llm-observability.md) |
| 2 | Hermes install + Discord gateway + Bani (admin) profile | ⬜ Next | — |
| 3 | DB migrations — all schemas via dbmate | ⬜ | — |
| 4 | Alex (personal assistant) + finance-service MCP | ⬜ | — |
| 5 | personal-service MCP (habits, goals, tasks) | ⬜ | — |
| 6 | Business agents — Raha (CoS) + C-suite profiles | ⬜ | — |

---

## Credentials Needed

| Secret | Where to get |
|---|---|
| `OPENROUTER_API_KEY` | openrouter.ai → Keys |
| `LITELLM_MASTER_KEY` | Generate: `openssl rand -hex 16`, prefix `sk-nizam-` |
| `LITELLM_DB_PASSWORD` | Generate: `python3 -c "import secrets; print(secrets.token_urlsafe(24))"` |
| `DISCORD_BOT_TOKEN` | discord.com/developers → New App → Bot → Token (Step 2) |

All secrets live in `~/.nizam-dotfiles/secrets/nizam.env` (gitignored, sops-encrypted copy tracked).

---

## Invariants

- Every service gets its own PostgreSQL role and schema — blast radius of any compromise is one schema
- All systemd units are symlinked from the repo — `git pull` + `systemctl daemon-reload` is the deploy
- Observability ships with each step — metrics and Grafana panels added before moving on
- Model-agnostic everywhere — model choice is config (`config/litellm.yaml`), not code
- No hardcoded pricing — OpenRouter `/api/v1/models` is the source of truth, cached 24h in Redis
