# Debugging — Nizam-OS

Quick-reference for diagnosing any part of the stack. Work top-down: infra → proxy → metrics → agents.

---

## nizam-log — unified log viewer (start here)

Single command that shows system services → agent gateways → one-shot scripts in sequence:

```bash
bash ~/nizam-os/scripts/nizam-log.sh            # last 30 lines per section
bash ~/nizam-os/scripts/nizam-log.sh -n 100     # last 100 lines per section
bash ~/nizam-os/scripts/nizam-log.sh -f         # follow system journal live
bash ~/nizam-os/scripts/nizam-log.sh -s agents  # agents only
bash ~/nizam-os/scripts/nizam-log.sh -s scripts # one-shot scripts only
bash ~/nizam-os/scripts/nizam-log.sh -s metrics # metrics-llm only
```

Sections: `system` | `agents` | `scripts` | `metrics`

---

## One-shot script logs

Scripts sourcing `_log.sh` (wire-hermes-profile, watch-inventory, metrics-services, etc.) write to:
```
~/nizam-os/logs/scripts.log
```

Format: `TIMESTAMP [LEVEL] [script-name] message`

```bash
tail -f ~/nizam-os/logs/scripts.log      # follow live
tail -n 50 ~/nizam-os/logs/scripts.log   # last 50 lines
grep WARN ~/nizam-os/logs/scripts.log    # warnings only
grep ERROR ~/nizam-os/logs/scripts.log   # errors only
```

Rotated daily, 14 days kept, by logrotate. Config: `config/logrotate.nizam`.

> logrotate requires its config files to be owned by root — symlinks to user-owned files are rejected. `config/logrotate.nizam` is therefore **copied** (not symlinked) to `/etc/logrotate.d/nizam` by `install-symlinks.sh`. If you edit `config/logrotate.nizam`, re-run `sudo bash scripts/setup/install-symlinks.sh` to push the change.
>
> `su vazir vazir` in the config is required because the log dir is in the user homedir, not `/var/log` — without it logrotate refuses to rotate "insecure" user-owned paths.

---

## Full stack status

```bash
# System services
sudo systemctl is-active litellm-proxy metrics-llm.timer metrics-services.timer watcher-env watcher-inventory

# User services (run as vazir, no sudo)
systemctl --user is-active hermes-profile-watcher \
  hermes-gateway-admin hermes-gateway-assistant hermes-gateway-cos hermes-gateway-curator

# Infrastructure
sudo systemctl is-active postgresql redis-server prometheus prometheus-node-exporter grafana-server

# All enabled nizam/hermes units
sudo systemctl list-unit-files --state=enabled | grep -E "litellm|metrics|watcher|hermes|grafana|prometheus|postgres|redis"
```

---

## Infrastructure

### PostgreSQL

```bash
sudo systemctl status postgresql --no-pager
sudo journalctl -u postgresql -n 30 --no-pager

# Test connection as svc_litellm
psql "postgresql://svc_litellm:<password>@127.0.0.1:5432/nizam" -c "\dn"

# Check schemas
psql "postgresql://svc_litellm:<password>@127.0.0.1:5432/nizam" -c "\dn+"

# Recent spend logs (confirm LiteLLM is writing)
psql "postgresql://svc_litellm:<password>@127.0.0.1:5432/nizam" \
  -c 'SELECT model, user_id, spend, "startTime" FROM litellm."LiteLLM_SpendLogs" ORDER BY "startTime" DESC LIMIT 5;'
```

### Redis

```bash
sudo systemctl status redis-server --no-pager
redis-cli ping          # expect: PONG
redis-cli info server | grep redis_version
redis-cli get nizam:openrouter:model_prices | python3 -m json.tool | head -20   # model price cache
```

### Prometheus

```bash
sudo systemctl status prometheus --no-pager
curl -s http://localhost:9090/-/healthy    # expect: Prometheus Server is Healthy.

# Check nizam metrics are being scraped
curl -s "http://localhost:9090/api/v1/label/__name__/values" | python3 -m json.tool | grep nizam

# Query a specific metric
curl -s "http://localhost:9090/api/v1/query?query=nizam_llm_proxy_up" | python3 -m json.tool

# Check node-exporter is up
curl -s http://localhost:9100/metrics | grep nizam_ | head -10
```

### Grafana

```bash
sudo systemctl status grafana-server --no-pager
sudo journalctl -u grafana-server -n 30 --no-pager

# Restart after config/plugin change
sudo systemctl restart grafana-server && sleep 3 && sudo systemctl is-active grafana-server
```

---

## LiteLLM proxy

```bash
sudo systemctl status litellm-proxy --no-pager
sudo journalctl -u litellm-proxy -n 50 --no-pager
sudo journalctl -u litellm-proxy -f    # follow live

# Health check
curl -s http://localhost:4000/health/liveliness    # expect: {"status":"healthy"}
curl -s http://localhost:4000/health/readiness

# Test a call (replace LITELLM_MASTER_KEY)
source ~/nizam-os/secrets/nizam.env
curl -s -X POST http://localhost:4000/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"openai/gpt-4o-mini","messages":[{"role":"user","content":"pong"}],"user":"debug"}'

# View spend logs via API (used by metrics-llm.py)
curl -s "http://localhost:4000/spend/logs?limit=5" \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" | python3 -m json.tool | head -40

# Restart
sudo systemctl restart litellm-proxy && sleep 5 && sudo systemctl status litellm-proxy --no-pager

# If stuck in failed state
sudo systemctl reset-failed litellm-proxy && sudo systemctl start litellm-proxy
```

---

## Metrics collector (metrics-llm.py)

```bash
sudo systemctl status metrics-llm.service --no-pager
sudo systemctl status metrics-llm.timer --no-pager
sudo journalctl -u metrics-llm.service -n 40 --no-pager

# Trigger manually and check output immediately
sudo systemctl start metrics-llm.service && cat /var/lib/prometheus/node-exporter/nizam-llm.prom

# Confirm proxy_up = 1 (if 0, LiteLLM is unreachable or LITELLM_MASTER_KEY wrong)
grep proxy_up /var/lib/prometheus/node-exporter/nizam-llm.prom

# See all metrics written
cat /var/lib/prometheus/node-exporter/nizam-llm.prom

# Check file freshness (should update every 60s)
ls -la /var/lib/prometheus/node-exporter/nizam-llm.prom

# Run script directly to see Python errors
sudo -E LITELLM_MASTER_KEY=$LITELLM_MASTER_KEY uv run scripts/metrics-llm.py
```

---

## Hermes — agents

### All gateways

```bash
hermes gateway list      # shows all installed gateways and status
hermes gateway status    # summary

hermes profile list      # shows all profiles, active one has ◆
```

### Per-profile

```bash
# Replace <name> with: admin, assistant, cos, curator, etc.
<name> gateway status
journalctl --user -u hermes-gateway-<name> -n 40 --no-pager
journalctl --user -u hermes-gateway-<name> -f    # follow live

# Restart a gateway
<name> gateway restart

# Check profile symlinks are correct (should all show -> /home/vazir/nizam-os/...)
ls -la ~/.hermes/profiles/<name>/
```

### Profile watcher

```bash
systemctl --user status hermes-profile-watcher --no-pager
journalctl --user -u hermes-profile-watcher -n 50 --no-pager
journalctl --user -u hermes-profile-watcher -f    # follow watcher events live

# Restart after script changes
systemctl --user restart hermes-profile-watcher

# Confirm 3 inotifywait processes are running (bidirectional + env-encrypt)
ps aux | grep inotifywait | grep -v grep
```

---

## Watchers

| Watcher | Unit | What it does |
|---|---|---|
| watcher-env | `watcher-env.service` | Watches `nizam.env`, auto-encrypts on change |
| watcher-inventory | `watcher-inventory.timer` | Hourly: diffs software+service inventory, notifies Discord |
| metrics-services | `metrics-services.timer` | Every 5 min: reads `services.txt`, writes `nizam-services.prom` for Grafana system health row |

```bash
sudo systemctl status <unit> --no-pager
sudo journalctl -u <unit> -n 20 --no-pager
```

Manual triggers:

```bash
# watcher-inventory — check last generated
cat ~/nizam-os/inventory/services.txt && ls -la ~/nizam-os/inventory/

# metrics-services — trigger and verify
sudo systemctl start metrics-services.service && cat /var/lib/prometheus/node-exporter/nizam-services.prom

# Confirm Prometheus is scraping
curl -s "http://localhost:9090/api/v1/query?query=nizam_services_total" | python3 -m json.tool | grep value
```

> `metrics-services` depends on `watcher-inventory` having run first. If `nizam-services.prom` is missing or stale, run `sudo systemctl start watcher-inventory.service` then `sudo systemctl start metrics-services.service`.

---

## Symlinks

```bash
# Verify all system units are symlinked (not copies)
ls -la /etc/systemd/system/litellm-proxy.service \
       /etc/systemd/system/metrics-llm.service \
       /etc/systemd/system/metrics-llm.timer \
       /etc/systemd/system/metrics-services.service \
       /etc/systemd/system/metrics-services.timer \
       /etc/systemd/system/watcher-env.service \
       /etc/systemd/system/watcher-inventory.service

# Verify user unit
ls -la ~/.config/systemd/user/hermes-profile-watcher.service

# Verify hermes profile symlinks for a given profile
ls -la ~/.hermes/profiles/admin/
# .env, config.yaml, *.md should be -> /home/vazir/nizam-os/...
# skills/ and memories/ should be -> /home/vazir/nizam-os/...
```

---

## Common fixes

| Symptom | Command |
|---|---|
| Service stuck in `failed` | `sudo systemctl reset-failed <unit> && sudo systemctl start <unit>` |
| Changed a systemd unit file | `sudo systemctl daemon-reload && sudo systemctl restart <unit>` |
| Changed user service | `systemctl --user daemon-reload && systemctl --user restart <unit>` |
| metrics-llm writes only `proxy_up 1`, no other metrics | Check `LITELLM_MASTER_KEY` in `~/nizam-os/secrets/nizam.env` (loaded via `EnvironmentFile`) |
| Grafana dashboard shows "No data" | Check Prometheus datasource UID is `nizam-prometheus`; check `nizam_llm_proxy_up` query in Prometheus UI |
| Hermes gateway not connecting to Discord | `journalctl --user -u hermes-gateway-<name> -f` — usually bad `DISCORD_BOT_TOKEN` or missing Privileged Intents |
| Profile files not symlinking | Run `bash ~/nizam-os/scripts/setup/wire-hermes-profile.sh <name>` |
| `.env.enc` out of date | `bash ~/nizam-os/scripts/encrypt-profile-env.sh <name>` — or just edit the `.env` and the watcher auto-encrypts |

---

## Data flow checkpoints

```bash
Discord message
  → hermes-gateway-<name>          journalctl --user -u hermes-gateway-<name> -f
      → LiteLLM proxy :4000        curl localhost:4000/health/liveliness
          → OpenRouter              curl localhost:4000/spend/logs?limit=1 (check response)
          → PostgreSQL SpendLogs    psql ... -c 'SELECT ... FROM litellm."LiteLLM_SpendLogs" LIMIT 1'
  → metrics-llm.py (60s timer)     cat /var/lib/prometheus/node-exporter/nizam-llm.prom
      → Prometheus                  curl localhost:9090/api/v1/query?query=nizam_llm_proxy_up
          → Grafana dashboard       check panel "Proxy Status" shows UP
```
