# Step 1 — LLM Observability Stack

Gives you: LiteLLM proxy → OpenRouter → spend logs in PostgreSQL → metrics every 60s → Grafana dashboard.

---

## Prerequisites

These must already be running before starting:

```bash
systemctl is-active postgresql redis-server prometheus prometheus-node-exporter grafana-server
# all should return: active
```

Also required:
- `uv` installed (`which uv`)
- `~/.nizam-dotfiles/` repo present (machine config — shell, security monitoring)
- OpenRouter API key (from openrouter.ai)
- Bitwarden (to store generated secrets)

---

## 1. uv Workspace

```bash
cd ~/.nizam-os
uv init --no-package
echo "3.12" > .python-version
uv lock
```

> Standard uv workspace at repo root. `members = ["services/*"]` in pyproject.toml means future MCP services added under `services/` are auto-included. Single `uv.lock` tracks all deps in git.

Verify:
```bash
uv run python --version   # Python 3.12.x
```

---

## 2. LiteLLM Config

File: `config/litellm.yaml`

Key decisions:
- `model_name: "*"` wildcard routes any model string through to `openrouter/*` — zero config when switching models
- `cache: true` with Redis — identical requests return cached responses, not billed again
- `store_end_user: true` — Hermes passes profile name as `user` field, recorded in SpendLogs, shows up as `profile` label in metrics
- `disable_spend_logs: false` — every request logged to PostgreSQL `litellm."LiteLLM_SpendLogs"`

---

## 3. Secrets

File: `~/.nizam-os/secrets/nizam.env` (plaintext, gitignored, encrypted copy tracked as `nizam.env.enc`)

```bash
OPENROUTER_API_KEY=sk-or-v1-...         # from openrouter.ai dashboard
LITELLM_MASTER_KEY=sk-nizam-...         # generate: openssl rand -hex 16, prefix with sk-nizam-
LITELLM_DB_PASSWORD=...                 # generate: python3 -c "import secrets; print(secrets.token_urlsafe(24))"
LITELLM_DB_URL=postgresql://svc_litellm:<password>@127.0.0.1:5432/nizam?schema=litellm
REDIS_URL=redis://localhost:6379/0
```

> Use `127.0.0.1` not `localhost` in `LITELLM_DB_URL`. On some systems `localhost` resolves to `::1` (IPv6) which PostgreSQL rejects with peer auth.

> Avoid special characters (`!`, `@`, `#`) in generated passwords — they trigger shell history expansion when used in CLI commands during setup.

---

## 4. PostgreSQL Setup

```bash
LITELLM_DB_PASSWORD='your-password' bash scripts/setup/setup-db.sh
```

What it creates:
- Database: `nizam` (all services share this, separated by schema)
- User: `svc_litellm` with password
- Schema: `litellm` owned by `svc_litellm`
- Default privileges so Prisma-created tables are accessible

Verify:
```bash
psql "postgresql://svc_litellm:<password>@127.0.0.1:5432/nizam" -c "\dn"
# should show: litellm schema
```

---

## 5. Install LiteLLM

```bash
uv tool install 'litellm[proxy]' --with prisma --force
```

> `--with prisma` is required. LiteLLM uses Prisma ORM to manage its DB schema. Without it, the proxy crashes at startup with `ModuleNotFoundError: No module named 'prisma'`.

Verify:
```bash
litellm --version   # 1.89.x or later
```

---

## 6. Prisma Schema Setup

Prisma needs its binary generated before LiteLLM can use the DB. Run once after install (and after any `uv tool upgrade litellm`):

```bash
SCHEMA=/home/vazir/.local/share/uv/tools/litellm/lib/python3.12/site-packages/litellm/proxy/schema.prisma

export PATH="/home/vazir/.local/share/uv/tools/litellm/bin:$PATH"

DATABASE_URL="postgresql://svc_litellm:<password>@127.0.0.1:5432/nizam?schema=litellm" \
  prisma generate --schema="$SCHEMA"

DATABASE_URL="postgresql://svc_litellm:<password>@127.0.0.1:5432/nizam?schema=litellm" \
  prisma db push --schema="$SCHEMA" --accept-data-loss
```

Verify:
```bash
psql "postgresql://svc_litellm:<password>@127.0.0.1:5432/nizam" -c "\dt litellm.*" | grep SpendLogs
# should show: litellm | LiteLLM_SpendLogs | table | svc_litellm
```

---

## 7. Systemd Units + Symlinks

Units live in `~/.nizam-os/systemd/`. Deployed via symlinks into `/etc/systemd/system/` — originals stay in the repo, system reads through the symlink.

> Same pattern as existing dotfiles services (`metrics-security`, `watcher-*`). Keeps all config in git, no manual copy step on updates.

```bash
sudo bash scripts/setup/install-symlinks.sh
sudo systemctl enable --now litellm-proxy metrics-llm.timer
```

Verify:
```bash
sudo systemctl status litellm-proxy --no-pager   # active (running)
sudo systemctl status metrics-llm.timer --no-pager   # active (waiting)
```

---

## 8. Test the Proxy

```bash
curl -s -X POST http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"openai/gpt-4o-mini","messages":[{"role":"user","content":"pong"}],"user":"test"}'
```

Expect: JSON response with `choices[0].message.content`.

Verify spend was logged:
```bash
psql "postgresql://svc_litellm:<password>@127.0.0.1:5432/nizam" \
  -c 'SELECT model, spend, prompt_tokens FROM litellm."LiteLLM_SpendLogs" ORDER BY "startTime" DESC LIMIT 3;'
```

---

## 9. Metrics Collector

Script: `scripts/metrics-llm.py`

Runs every 60s as root (system timer). Queries SpendLogs, fetches OpenRouter pricing (cached 24h in Redis), writes `/var/lib/prometheus/node-exporter/nizam-llm.prom`.

> Python not shell: needs PostgreSQL client, Redis client, HTTP + JSON parsing across nested objects. Shell would be brittle. Same textfile output pattern as `metrics-security.sh`.

> `?schema=litellm` in `LITELLM_DB_URL` is Prisma syntax. psycopg2 doesn't understand it — the script strips it before connecting. Queries use fully-qualified `litellm."TableName"` so no search_path needed.

Trigger manually and verify:
```bash
sudo systemctl start metrics-llm.service
cat /var/lib/prometheus/node-exporter/nizam-llm.prom | grep proxy_up
# should show: nizam_llm_proxy_up 1
```

Verify Prometheus is scraping it:
```bash
curl -s "http://localhost:9090/api/v1/query?query=nizam_llm_proxy_up" | python3 -m json.tool | grep value
```

---

## 10. Grafana

> Grafana's systemd unit has `ProtectHome=true` which blocks symlinks into `/home/`. Manual setup avoids this entirely and takes 2 minutes.

1. **Datasource**: Connections → Data sources → Add → Prometheus
   - URL: `http://localhost:9090`
   - UID: `nizam-prometheus`
   - Save & test → should show green

2. **Dashboard**: Dashboards → New → Import → upload `~/.nizam-os/grafana/agents-dashboard.json`

Verify in dashboard:
- `Proxy Status` panel shows **UP**
- `Calls Today` shows at least 1
- Model/Agent dropdowns populate from actual call history

---

## Full Stack Verify

```bash
# All services running
sudo systemctl is-active litellm-proxy metrics-llm.timer grafana-server prometheus

# Proxy health
curl -s http://localhost:4000/health/liveliness   # "I'm alive!"

# Metrics file fresh (timestamp within last 2 min)
ls -la /var/lib/prometheus/node-exporter/nizam-llm.prom

# Prometheus has our metrics
curl -s "http://localhost:9090/api/v1/label/model/values" | python3 -m json.tool
# should list models from your test calls
```

---

## Inventory

New entries added to `~/.nizam-os/inventory/tracked-services.txt`:
```
# Nizam-OS — LLM Gateway
litellm-proxy.service
metrics-llm.service
metrics-llm.timer
```
