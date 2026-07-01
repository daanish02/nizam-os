# Admin v1 — design spec

**Status:** approved, pending implementation
**Date:** 2026-07-01
**Scope:** Make the admin profile (Nazim) bulletproof — automated code-based monitoring that fires without Nazim being alive, plus complete the manual health check procedure.

---

## Problem

Nazim's HEARTBEAT.md is a manual procedure run on-demand. Nothing monitors the system automatically. If Hermes itself dies, there is no alert. If PostgreSQL or Redis goes down, nobody knows until something downstream breaks. The health monitor must be code-only — no LLM in the alert path.

---

## What this spec covers

| Area | Change |
|---|---|
| `scripts/health-monitor.py` | New: code-only health monitor with auto-restart and Discord alerts |
| `systemd/health-monitor.service` | New: systemd unit, system-level |
| `systemd/health-monitor.timer` | New: fires every 2 minutes |
| `inventory/tracked-services.txt` | Update: annotate each service as `critical` or `watch` |
| `hermes/profiles/admin/HEARTBEAT.md` | Update: add all missing services, align with monitor scope |
| `hermes/profiles/admin/SOUL.md` | Personality and tone only (per Hermes docs); rename Bani → Nazim |
| `hermes/profiles/admin/AGENTS.md` | New: mandate, incident response, HEARTBEAT procedure pointer, bulletproof rules |
| Admin Hermes cron | Wire daily health check at 08:00 to `#admin` (model pinned) |

> **TOOLS.md dropped.** Admin uses only Hermes native tools (terminal, file, web) — no custom MCP servers. Nothing to document.
>
> **All files renaming Bani → Nazim:** SOUL.md, PROTOCOL.md, HEARTBEAT.md, TOOLS.md (if kept). Update every occurrence.

## Out of scope (future specs)

- Firejail sandboxing for CTO sub-agents
- WhatsApp or SMS alert fallback
- Disk-space-triggered cleanup
- Log anomaly detection

---

## Service tiers

The monitor reads `inventory/tracked-services.txt`. Each tracked service is annotated with a tier comment.

**Critical** — down triggers restart attempt + Discord alert:

| Service | Type |
|---|---|
| `postgresql.service` | system |
| `redis-server.service` | system |
| `litellm-proxy.service` | system |
| `hermes-gateway-admin.service` | user |
| `hermes-gateway-curator.service` | user |

**Watch** — down triggers Discord alert only, no restart:

| Service | Type |
|---|---|
| `grafana-server.service` | system |
| `prometheus.service` | system |
| `prometheus-node-exporter.service` | system |
| `fail2ban.service` | system |
| `tailscaled.service` | system |
| `hermes-gateway-assistant.service` | user |
| `hermes-gateway-cos.service` | user |
| `metrics-llm.timer` | system |
| `metrics-services.timer` | system |
| `metrics-toolcalls.timer` | system |
| `hermes-profile-watcher.service` | user |

---

## Auto-restart logic

Restart cap: **2 restarts per service per hour**. Tracked in Redis.

```
Redis key:  nizam:health:restarts:{service_name}
Value:      integer restart count
TTL:        3600 seconds (1 hour, rolling)
```

On each check cycle per failing critical service:

```
count = Redis.GET(key) or 0

if count < 2:
    systemctl restart <service>
    Redis.INCR(key)
    Redis.EXPIRE(key, 3600)
    post: "Restarted {service} (attempt {count+1}/2). Status: {result}."

elif count == 2:
    post: "Restart cap reached for {service} — manual intervention required."
    # No further restart attempts until TTL expires
```

Recovery: when a previously-failed service returns to `active`, post a recovery notification and delete the Redis key.

User services (`hermes-gateway-*.service`) require `systemctl --user` with `DBUS_SESSION_BUS_ADDRESS` set. The monitor reads this from `/run/user/{uid}/bus` at startup.

---

## Discord alert format

All alerts post to `DISCORD_ADMIN_WEBHOOK` as a JSON embed.

**Failure / restart attempt:**
```json
{
  "embeds": [{
    "title": "SERVICE DOWN",
    "color": 15158332,
    "fields": [
      {"name": "Service", "value": "{service}", "inline": true},
      {"name": "Tier",    "value": "critical | watch", "inline": true},
      {"name": "Action",  "value": "Restarted (1/2) — active | Restart cap reached | No action (watch)", "inline": false}
    ],
    "timestamp": "{ISO-8601}"
  }]
}
```

**Recovery:**
```json
{
  "embeds": [{
    "title": "SERVICE RECOVERED",
    "color": 3066993,
    "fields": [
      {"name": "Service", "value": "{service}", "inline": true},
      {"name": "Was down", "value": "{N} checks", "inline": true}
    ],
    "timestamp": "{ISO-8601}"
  }]
}
```

Repeated failures (service stays down across multiple cycles) post **once per state transition** — not every 2 minutes. State is stored in Redis:

```
Redis key:  nizam:health:state:{service_name}
Value:      "up" | "down"
TTL:        none (persists until updated)
```

Alert fires only on `up → down` or `down → up` transitions.

---

## `scripts/health-monitor.py` — design

```python
#!/usr/bin/env python3
"""
Code-only system health monitor for nizam-os.
Checks all tracked services, auto-restarts critical ones (cap: 2/hour),
posts Discord alerts on state transitions.
Runs every 2 minutes via health-monitor.timer.
"""
```

**Dependencies:** `httpx` and `redis` added to root `pyproject.toml` dependencies (currently empty). Running `uv run --directory /home/vazir/nizam-os python scripts/health-monitor.py` then resolves them from the workspace lockfile. No new workspace member needed.

**Env vars read** (from `secrets/nizam.env`):
- `DISCORD_ADMIN_WEBHOOK` — webhook URL for alerts
- `REDIS_URL` — defaults to `redis://localhost:6379/0`

**Service list source:** parses `inventory/tracked-services.txt` — lines with `# critical` annotation are critical tier, lines with `# watch` (or unannotated) are watch tier.

**Execution flow:**
1. Load env, connect Redis
2. Resolve user service DBUS address for `vazir` user
3. For each tracked service: check `systemctl is-active`
4. Compare against stored state in Redis
5. On `down` transition: attempt restart (critical) or skip (watch) → post alert
6. On `up` transition: clear restart counter → post recovery
7. Exit cleanly — timer re-fires in 2 minutes

---

## Systemd units

**`systemd/health-monitor.service`:**
```ini
[Unit]
Description=Nizam-OS health monitor
After=network.target redis-server.service

[Service]
Type=oneshot
User=vazir
EnvironmentFile=/home/vazir/nizam-os/secrets/nizam.env
ExecStart=/home/vazir/.local/bin/uv run --directory /home/vazir/nizam-os \
    --env-file /home/vazir/nizam-os/secrets/nizam.env \
    python scripts/health-monitor.py
StandardOutput=journal
StandardError=journal
```

**`systemd/health-monitor.timer`:**
```ini
[Unit]
Description=Run Nizam-OS health monitor every 2 minutes

[Timer]
OnBootSec=60
OnUnitActiveSec=2min
Persistent=true

[Install]
WantedBy=timers.target
```

System-level (not user), so it survives Hermes restarts and logout. Symlink into `/etc/systemd/system/` like all other nizam-os units.

---

## `inventory/tracked-services.txt` changes

Add tier annotations as inline comments:

```
# Infrastructure
postgresql.service | system | active  # critical
redis-server.service | system | active  # critical
litellm-proxy.service | system | active  # critical
grafana-server.service | system | active  # watch
prometheus.service | system | active  # watch
...

# Nizam-OS — Hermes Gateway
hermes-gateway-admin.service | user | active  # critical
hermes-gateway-curator.service | user | active  # critical
hermes-gateway-assistant.service | user | inactive  # watch
hermes-gateway-cos.service | user | inactive  # watch
```

The monitor skips services whose inventory line contains `| inactive` — they are intentionally down and not expected to be running. Parser: split each non-comment, non-empty line on `|`, read the third field, strip whitespace, skip if `== "inactive"`.

---

## HEARTBEAT.md update

Current HEARTBEAT.md checks 5 services manually. Update to check all 20+ in the tracked list, grouped by tier. Add:

- PostgreSQL: `pg_isready -U postgres`
- Redis: `redis-cli ping` → expect `PONG`
- knowledge-service reachability: `uv run python -c "from nizam_shared.base import ServiceBase; ServiceBase('test')"` (connection smoke test)
- All Hermes gateways: `systemctl --user is-active hermes-gateway-{admin,curator,assistant,cos}.service`
- Metric freshness: check all `.prom` files, not just a subset

---

## SOUL.md — Nazim profile

**What goes here:** personality, tone, communication style ONLY.

```markdown
You are Nazim, the system administrator of nizam-os.

You are methodical, precise, and cautious. You never take destructive actions
without explicit approval. When something is wrong, you report the exact state
and ask before acting — unless it is a clear auto-restart situation already
defined in AGENTS.md.

You do not use emojis. All responses are Discord-formatted. Incident reports
use the embed format defined in PROTOCOL.md.
```

---

## AGENTS.md — Nazim profile

`hermes/profiles/admin/AGENTS.md` — mandate and operating rules.

```markdown
# Nazim — System Administrator

## Mandate
You are the system administrator of nizam-os running on a VPS. Your job is to
keep all services healthy, respond to incidents, and produce accurate health reports.

## Bulletproof rules
- Never delete files without explicit user approval.
- Never run `systemctl stop` or `systemctl disable` without explicit user approval.
- Never modify nizam.env or any secrets file.
- Never restart a service more than twice without user confirmation.
- If uncertain whether an action is safe, stop and ask.

## Health check procedure
See HEARTBEAT.md in this directory. Run it when asked. Post results to #admin.

## Incident response
See PROTOCOL.md in this directory. Follow it exactly on any P1/P2 incident.

## Services inventory
See ~/nizam-os/inventory/tracked-services.txt for the full list.
Critical services (auto-restart eligible): postgresql, redis-server, litellm-proxy,
hermes-gateway-admin, hermes-gateway-curator.
Watch services (alert only): everything else.
```

---

## Nazim profile — `config.yaml`

Key config additions. No MCP servers — Nazim uses Hermes native tools only.

```yaml
discord:
  allowed_channels: "<admin_id>,<system_id>"   # only Nazim's channels

agent:
  disabled_toolsets:
    - browser
    - code_execution
    - delegation
    - image_gen
    - tts
    - vision
    - web
  # Keep: terminal, file, memory, skills, clarify, cronjob

security:
  allow_lazy_installs: false
  redact_secrets: true

approvals:
  mode: manual

command_allowlist:
  - systemctl restart
  - journalctl
  - pg_isready
  - redis-cli ping

auxiliary:
  compression:
    provider: custom:litellm
    model: deepseek/deepseek-v3-0324
```

Sudo access: configured via `/etc/sudoers.d/nazim-hermes` (targeted NOPASSWD for specific restart commands only). See `each agent's individual spec`.

---

## Admin Hermes cron

Wire Nazim's daily health check using Hermes's built-in cron feature. This is configured inside the Hermes profile, not as a systemd unit.

**Model must be pinned** — per Hermes docs, unpinned cron jobs fail closed if the global model changes. Wire via CLI inside the admin profile:

```bash
nazim cron create "0 8 * * *" \
  "Run the health check procedure in HEARTBEAT.md. Post the result to #admin." \
  --name "daily-health" \
  --provider "custom:litellm" \
  --model "deepseek/deepseek-v4-flash"
```

Or via in-chat `cronjob` tool with `provider` and `model` explicitly set.

This is separate from the code monitor — Nazim's cron gives a human-readable daily summary; the monitor handles real-time alerting.

---

## `inventory/tracked-services.txt` — add health-monitor

Add the new unit to the inventory so it tracks itself:

```
health-monitor.timer | system | active  # watch
```

---

## Implementation order

1. Rename Bani → Nazim in all admin profile files (SOUL.md, PROTOCOL.md, HEARTBEAT.md)
2. Write admin `SOUL.md` (personality only) and `AGENTS.md` (mandate + rules)
3. Annotate `inventory/tracked-services.txt` with tiers
4. Write `scripts/health-monitor.py`
5. Write `systemd/health-monitor.service` + `health-monitor.timer`
6. Install units: symlink → `daemon-reload` → `enable` → `start`
7. Update `HEARTBEAT.md`
8. Wire admin cron (pinned model)

---

## What "done" looks like

- `health-monitor.timer` running at system level, fires every 2 minutes
- Taking postgresql or redis down triggers a Discord alert within 2 minutes
- Service auto-restarts (critical tier), posts result
- Two failed restarts → cap alert, no further attempts for 1 hour
- Recovery posts a green embed
- Same failure does not spam Discord — one alert per state transition
- Nazim posts a daily health summary to `#admin` at 08:00
- HEARTBEAT.md reflects all 20+ services
- All "Bani" references gone from admin profile files
