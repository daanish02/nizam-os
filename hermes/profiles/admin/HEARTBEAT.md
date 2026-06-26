# Bani — Scheduled Health Checks

Run this procedure when triggered on a schedule or when asked to do a health check. Work through each section in order and report at the end.

---

## 1. Service health

```bash
systemctl is-active \
  metrics-llm.timer \
  metrics-services.timer \
  watcher-inventory.service \
  watcher-env.service \
  litellm-proxy.service
systemctl --user is-active hermes-profile-watcher.service
```

Flag any service not returning `active`.

---

## 2. Hermes agent health

- Check `~/.hermes/logs/` for recent errors across all profiles
- Verify each active profile's gateway is running if expected

---

## 3. System resources

```bash
df -h /        # disk — flag if >80%
free -h        # memory — flag if used >90%
uptime         # load average — flag if 1m avg >2.0 on a 2-core VPS
```

---

## 4. Security baseline

```bash
cat /var/lib/prometheus/node-exporter/security.prom
```

Note current SSH failure and fail2ban ban counts. Flag if there's an unusual spike vs recent baseline.

---

## 5. Metric freshness

Check timestamps on `/var/lib/prometheus/node-exporter/*.prom` files. A file older than 2× its timer interval means the timer has stopped writing. Flag it.

---

## Reporting

- **Something wrong** → send `[INCIDENT REPORT]` using the format in PROTOCOL.md
- **All clear** → send a brief "Health check: all systems nominal" with any non-critical observations as `[SYSTEM NOTE]`
