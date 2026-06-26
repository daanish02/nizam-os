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
sudo systemctl enable --now litellm-proxy metrics-llm.timer metrics-services.timer
```

Verify:
```bash
sudo systemctl status litellm-proxy --no-pager        # active (running)
sudo systemctl status metrics-llm.timer --no-pager    # active (waiting)
sudo systemctl status metrics-services.timer --no-pager   # active (waiting)
```

`metrics-services.timer` runs every 5 min, reads `inventory/tracked-services.txt`, writes `/var/lib/prometheus/node-exporter/nizam-services.prom` — powers the System Health row in the Grafana dashboard. Requires `watcher-inventory.timer` to have run at least once first (generates the source file).

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
sudo systemctl start metrics-llm.service && sleep 2 \
  && sudo journalctl -u metrics-llm.service -n 5 --no-pager
```

Healthy output looks like:
```
[INFO ] [metrics-llm] fetched 28 spend log entries
[INFO ] [metrics-llm] wrote 15 series, today: 3 req / 1200+450 tok / $0.0012, month: $0.0034
```

- `fetched 0 entries` → LiteLLM has no logs yet (normal on fresh install)
- `fetched N entries` but no second line → crash after fetch; check full journal (`-n 30`)
- No lines at all, service failed → `LITELLM_MASTER_KEY` not set or proxy unreachable
- `wrote N series` → success; prom file updated

```bash
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

---

## Troubleshooting

### LiteLLM proxy won't start

```bash
sudo journalctl -u litellm-proxy -n 50 --no-pager

# Reset if stuck in failed
sudo systemctl reset-failed litellm-proxy && sudo systemctl start litellm-proxy

# Check env vars are loaded (service reads from nizam.env via EnvironmentFile)
sudo systemctl cat litellm-proxy | grep EnvironmentFile
sudo systemctl show litellm-proxy -p Environment
```

### Proxy starts but calls fail / 401

```bash
# Confirm key matches what's in nizam.env
source ~/.nizam-os/secrets/nizam.env
curl -s http://localhost:4000/health/liveliness -H "Authorization: Bearer $LITELLM_MASTER_KEY"

# Check OpenRouter key is valid
curl -s https://openrouter.ai/api/v1/models \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" | python3 -m json.tool | head -10
```

### metrics-llm.prom only shows `proxy_up 1`, nothing else

```bash
# Most common: LITELLM_MASTER_KEY not passed to the timer service
sudo systemctl cat metrics-llm.service | grep -i key

# Run manually with key to see Python errors
source ~/.nizam-os/secrets/nizam.env
sudo -E LITELLM_MASTER_KEY=$LITELLM_MASTER_KEY uv run scripts/metrics-llm.py

# Check LiteLLM spend API directly
curl -s "http://localhost:4000/spend/logs?limit=3" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" | python3 -m json.tool
```

### Prometheus not scraping nizam metrics

```bash
# Confirm node-exporter textfile dir has the prom file
ls -la /var/lib/prometheus/node-exporter/

# Check node-exporter exposes it
curl -s http://localhost:9100/metrics | grep nizam_

# Check prometheus config includes node-exporter
sudo cat /etc/prometheus/prometheus.yml | grep -A5 node

# Force metrics-llm to run now
sudo systemctl start metrics-llm.service && sleep 2 \
  && curl -s "http://localhost:9090/api/v1/query?query=nizam_llm_proxy_up" | python3 -m json.tool
```

### Grafana dashboard shows "No data"

```bash
# 1. Check datasource UID matches dashboard expectation
#    Dashboards → Connections → Data sources → Prometheus → UID must be: nizam-prometheus

# 2. Check Prometheus has the metric at all
curl -s "http://localhost:9090/api/v1/label/__name__/values" \
  | python3 -m json.tool | grep nizam

# 3. Check Grafana can reach Prometheus
sudo journalctl -u grafana-server -n 20 --no-pager | grep -i "error\|datasource"
```

### Prisma / SpendLogs table missing

```bash
# Regenerate prisma schema (run after litellm upgrade too)
SCHEMA=/home/vazir/.local/share/uv/tools/litellm/lib/python3.12/site-packages/litellm/proxy/schema.prisma
export PATH="/home/vazir/.local/share/uv/tools/litellm/bin:$PATH"
source ~/.nizam-os/secrets/nizam.env

DATABASE_URL="postgresql://svc_litellm:$LITELLM_DB_PASSWORD@127.0.0.1:5432/nizam?schema=litellm" \
  prisma db push --schema="$SCHEMA" --accept-data-loss

# Verify table exists
psql "postgresql://svc_litellm:$LITELLM_DB_PASSWORD@127.0.0.1:5432/nizam" \
  -c '\dt litellm.*' | grep SpendLogs
```
