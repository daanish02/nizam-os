# Nizam-OS — Integrations

**Last updated:** 2026-07-01

Every external service the system connects to: purpose, credentials, rate limits, failure behavior. For env var details see `docs/SECRETS.md`.

---

## OpenRouter

**What:** Model routing API. All LLM inference routes through OpenRouter → LiteLLM proxy → agents.

**URL:** `https://openrouter.ai/api/v1`

**Auth:** `OPENROUTER_API_KEY` in `secrets/nizam.env`

**Headers sent with every request:**
```
HTTP-Referer: https://nizam-os
X-Title: Nizam-OS
```

**Models used:**
| Model | Used for |
|---|---|
| `deepseek/deepseek-v4-flash` | All agent inference (primary) |
| `deepseek/deepseek-v3-0324` | Compression (context summarisation) |
| `google/gemini-embedding-2` | Vault note embeddings (knowledge-service) |
| `google/gemini-2.0-flash` | Vision model for `ingest_image` (default, overridable via `VISION_MODEL`) |

**Rate limits:** Depends on OpenRouter credit balance. No hard request limit — pay-as-you-go. Monitor spend in Grafana (`agents-dashboard.json`).

**Failure behavior:** LiteLLM returns HTTP 5xx to the agent. Hermes retries (`api_max_retries: 3`). If OpenRouter is fully down: all agent inference fails; no local fallback.

---

## LiteLLM Proxy (internal)

**What:** Local model proxy on `localhost:4000`. Not an external service but is the intermediary to OpenRouter. Adds: spend tracking, Redis cache, per-profile virtual keys, token counting.

**Config:** `config/litellm.yaml`

**Admin UI:** `http://localhost:4000` (or via Tailscale) — view spend logs, virtual keys, cache stats.

**Spend tracking:** Requires Prisma migration run on first boot. Without it: proxy works but spend logs are not persisted. See `docs/RUNBOOK.md` → LiteLLM DB init.

**Cache:** Exact-match Redis cache (TTL 3600s). Identical prompt + model = cache hit, no OpenRouter call. Semantic cache: not yet configured.

---

## Discord

**What:** Primary user interface. Each agent is a Discord bot in the same server.

**Auth per profile:** `DISCORD_TOKEN` in `hermes/profiles/<name>/.env`. Server ID: `DISCORD_GUILD_ID` (same across all profiles).

For server structure, bot creation, intents, webhooks, channel IDs, and `DISCORD_ALLOWED_USERS` setup see `docs/DISCORD.md`.

---

## YouTube Data API v3

**What:** Tier 3 fallback for transcript fetching in `knowledge-service`. Used only when `youtube-transcript-api` (Tier 1) and `yt-dlp` (Tier 2) both fail.

**Auth:** `YOUTUBE_API_KEY` in `nizam.env`

**Quota:** 10,000 units/day (free tier). Transcript caption download = ~50 units. At typical usage (a few videos/day) this is never a constraint.

**Where used:** `services/knowledge-service/transcript.py` — `_tier3_youtube_api()` function.

**Failure behavior:** If API key is missing or quota is exhausted: returns `{"source": "youtube-api-v3-metadata"}` with video description as content. Confidence downgraded to `"low"`. Noor is notified via tool response.

**Get key:** console.cloud.google.com → APIs & Services → Credentials → Create Credentials → API Key → restrict to YouTube Data API v3.

---

## yt-dlp (Tier 2 transcript)

**What:** Local CLI tool. Second fallback for YouTube transcripts. Downloads VTT subtitle files, parses, deduplicates.

**Auth:** Optional. `YOUTUBE_COOKIES_FILE` path in `nizam.env` — points to a `cookies.txt` exported from a logged-in browser session. Needed if yt-dlp gets blocked by YouTube.

**Installation:** `pip install yt-dlp` or `uv add yt-dlp` in knowledge-service deps. Should already be in `pyproject.toml`.

**Failure behavior:** If VTT download fails: falls through to Tier 3 (YouTube Data API). No crash. If returning 429 or sign-in errors: see `docs/RUNBOOK.md` → yt-dlp cookie refresh.

---

## FX Rate API

**What:** Exchange rate lookups for multicurrency finance transactions. Used by `finance-service`.

**Provider:** `api.exchangerate-api.com` (free tier)

**Auth:** `FX_API_KEY` in `nizam.env`

**Free tier:** 1,500 requests/month. At one lookup per transaction (same-day rate cached in `finance.fx_rates`), this is sufficient for daily personal use.

**Caching:** Rate cached by date in `finance.fx_rates`. Same-day FX rate is reused — no duplicate API calls within a day.

**Failure behavior:** If API is unavailable: `finance-service` asks Ayah to surface the error. Ayah asks user to supply the rate manually. Transaction is not blocked.

**Currencies supported:** USD, AED, SAR, and most ISO 4217 codes. Verify SAR support before first transaction.

**Get key:** exchangerate-api.com → sign up → free tier → copy API key.

---

## Gold Price API

**What:** Current gold price in USD/gram for zakat nisab calculation. Used by `finance-service` → `calculate_zakat` tool.

**Provider:** `metals-api.com` or `goldpricez.com` (free tier — confirm at build time)

**Auth:** `GOLD_API_KEY` in `nizam.env`

**Usage frequency:** Fetched only at hawl calculation time (once per year). Not polled continuously.

**Caching:** Stored in `finance.zakat_hawl.gold_price_usd` after each calculation. Not re-fetched unless a new hawl is being calculated.

**Failure behavior:** If API is unavailable at hawl calculation time: `calculate_zakat` returns an error. Ayah asks user to supply the gold price manually. Not a blocking failure for day-to-day finance operations.

---

## GitHub (Reem / CTO)

**What:** Read access to nizam-os GitHub repo. Reem uses the official GitHub MCP server (`@modelcontextprotocol/server-github`) to review PRs, list issues, read commits.

**Auth:** `GITHUB_PAT` in `hermes/profiles/cto/.env` (per-profile, not in shared nizam.env)

**Required scopes (fine-grained PAT):**
- Contents: Read
- Pull requests: Read and write (write needed for `create_pull_request_review`)
- Issues: Read
- Metadata: Read

Never admin scope. Never `delete_*` tools.

**Runtime:** `npx -y @modelcontextprotocol/server-github` — pulled from npm at Hermes session start. Requires Node.js on VPS (`node --version`; install via nvm or apt if missing).

**Get token:** github.com → Settings → Developer settings → Fine-grained personal access tokens → Generate new token → select repo → set scopes above.

---

## Tailscale

**What:** VPN for VPS management access. Not used by agents — used by the human operator to SSH into and administer the VPS without exposing ports.

**Auth:** Tailscale account tied to VPS. Auth key generated at login.tailscale.com.

**UFW rule:** Tailscale subnet (`100.64.0.0/10`) is allowed inbound. SSH is only accessible via Tailscale IP in normal operations.

**Failure behavior:** If Tailscale is down: VPS is still reachable via public IP on port 22 (if UFW allows it) or via Hostinger VPS console.

**On fresh VPS:** Install and auth before closing the initial SSH session.

```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
# Follow the auth URL that appears
sudo tailscale status   # verify connected
```

---

## Prometheus + Grafana (internal observability)

Not external services but have their own integration surface.

**Prometheus:** `localhost:9090`. Scrapes `node-exporter` (system metrics) + textfile collector (nizam custom metrics from `.prom` files in `/var/lib/prometheus/node-exporter/`).

**Grafana:** `localhost:3000` (or via Tailscale). Datasource: Prometheus, UID must be `nizam-prometheus` (hardcoded in dashboard JSONs).

**Dashboard files:** `grafana/agents-dashboard.json`, `grafana/services-dashboard.json`. Import manually after Grafana install.

**Grafana PostgreSQL datasource** (personal + business dashboards, added in Assistant v1): connect as `grafana` role, SELECT-only. Credentials set in Grafana UI, not in nizam.env.
