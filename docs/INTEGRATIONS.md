# Integrations

Every external service or dependency the system connects to: what it is, why it's used, its auth surface, rate limits, and failure behavior.

---

## OpenRouter

**What:** Model routing API. All LLM inference routes through LiteLLM → OpenRouter.

**Why:** Single endpoint for 100+ model providers. Switching models means changing a config value — no code changes. Spend tracking at the proxy level.

**Auth:** `OPENROUTER_API_KEY` in `secrets/nizam-os.env`. Each agent uses a LiteLLM virtual key derived from this.

**Models in use:**

| Model | Used for |
|-------|---------|
| `deepseek/deepseek-v4-flash` | All agent inference (primary) |
| `deepseek/deepseek-v4-flash` | Context compression |
| `google/gemini-embedding-2` | Vault note embeddings |
| `google/gemini-2.0-flash` | Vision (image ingestion) |

**Rate limits:** Pay-as-you-go. No hard request limit — constrained only by credit balance. Monitored via Grafana spend dashboard.

**Failure mode:** LiteLLM returns HTTP 5xx to the agent. Hermes retries (`api_max_retries: 3`). If OpenRouter is fully down, all agent inference fails. No local fallback.

---

## Discord

**What:** Primary user interface. Each agent is a separate Discord bot in the same server.

**Why:** Always-on, mobile-accessible, notification-native. Separates domains into channels naturally.

**Auth:** One `DISCORD_TOKEN` per agent profile in `hermes/profiles/<name>/.env`. Shared `DISCORD_GUILD_ID` across all profiles.

**Failure mode:** If Discord is down, no interaction with agents is possible. Agents continue running but cannot receive or send messages.

Server structure, channel map, bot setup, and intents: [SPECS](docs/specs/).

---

## YouTube Data API v3

**What:** Tier 3 fallback for transcript fetching in `knowledge-service`.

**Why:** Used only when `youtube-transcript-api` (Tier 1) and `yt-dlp` (Tier 2) both fail.

**Auth:** `YOUTUBE_API_KEY` in `nizam-os.env`.

**Rate limits:** 10,000 units/day (free tier). Transcript caption download ≈ 50 units. Not a realistic constraint at personal usage volumes.

**Failure mode:** If unavailable or quota exhausted, falls back to video description metadata with confidence downgraded to `"low"`. Noor is notified via tool response.

---

## yt-dlp

**What:** Local CLI tool. Second fallback (Tier 2) for YouTube transcript download via VTT subtitles.

**Why:** Handles transcripts when `youtube-transcript-api` is blocked by YouTube.

**Auth:** Optional `YOUTUBE_COOKIES_FILE` in `nizam-os.env` — path to a `cookies.txt` from a logged-in browser session. Required if yt-dlp hits sign-in errors or 429s.

**Failure mode:** Falls through to Tier 3 (YouTube Data API). No crash.

---

## FX Rate API

**What:** Exchange rate lookups for multicurrency finance transactions.

**Provider:** `api.exchangerate-api.com` (free tier).

**Auth:** `FX_API_KEY` in `nizam-os.env`.

**Rate limits:** 1,500 requests/month (free tier). Sufficient for daily personal finance at one lookup per report run.

**Caching:** finance-service caches the rate for a configurable TTL to avoid burning quota. Detail: `docs/specs/`.

**Failure mode:** If unavailable, `finance-service` surfaces the error. Ayah asks the owner to supply the rate manually. Transaction logging is not blocked.

---

## Gold Price API

**What:** Current gold price in USD/gram for zakat nisab calculation.

**Provider:** TBD at build time (metals-api.com or equivalent free tier).

**Auth:** `GOLD_API_KEY` in `nizam-os.env`.

**Usage:** Fetched only at zakat calculation time — not polled continuously.

**Failure mode:** If unavailable, `calculate_zakat` returns an error. Ayah asks the owner to supply the gold price manually.

---

## GitHub (Reem only)

**What:** Read access to the nizam-os repo. Reem uses the official GitHub MCP server to review PRs, list issues, and read commits. Limited write access for PR operations.

**Auth:** `GITHUB_PAT` in `hermes/profiles/cto/.env` (per-profile — not in shared `nizam-os.env`).

**Required PAT scopes:** Contents read, Pull requests read+write, Issues read, Metadata read. No admin scope. No delete, no repo creation, no webhook management.

**Runtime:** `npx -y @modelcontextprotocol/server-github` pulled from npm at Hermes session start. Requires Node.js on VPS. This is a supply chain trust surface — pin the version when Reem is built. Detail: [SECURITY](docs/SECURITY.md) → Supply chain.

**Failure mode:** If npm is unavailable at session start, Reem's GitHub MCP fails to load. Reem continues to function without GitHub tools.

---

## Tailscale

**What:** VPN for VPS management. Used by the owner to SSH in and administer the VPS. Not used by agents.

**Why:** Avoids exposing SSH on the public internet as the primary access path.

**Auth:** Tailscale account linked to VPS. Auth key from login.tailscale.com.

**Failure mode:** If Tailscale is down, VPS is still reachable via public IP on port 22 (UFW allows it) or via Hostinger VPS console.

---

## LiteLLM Proxy (internal)

**What:** Local model proxy on `localhost:4000`. The single chokepoint between agents and any external model provider.

**Why:** Centralizes spend tracking, Redis caching (exact-match and future semantic), per-agent virtual keys, token counting, and rate limits. Switching model providers requires only a config change — no agent or service code changes.

**Auth:** Each Hermes agent profile carries a LiteLLM virtual key (derived from the master `OPENROUTER_API_KEY`). Agents connect to `http://localhost:4000` — they never see the OpenRouter key directly.

**Spend tracking:** Requires Prisma migration run on first boot. Without it, the proxy routes correctly but spend is not persisted.

**Cache:** Exact-match Redis cache (TTL configurable). Identical prompt + model = cache hit, no OpenRouter call. Semantic cache is planned.

**Failure mode:** If LiteLLM is down, all agent inference fails. Restart via systemd: `systemctl --user restart litellm`.

---

## Langfuse (internal, on-demand)

**What:** Self-hosted LLM observability platform. Traces agent LLM calls — prompt, response, token counts, latency, model, cost — for debugging and evaluation.

**Why:** When an agent behaves unexpectedly, Langfuse lets you inspect the exact prompt and response at each step. Not needed in normal operation — enabled only during active debugging or tracing sessions.

**How it's toggled:** Langfuse integration is controlled via an environment variable in `nizam-os.env`. When `LANGFUSE_ENABLED=true`, LiteLLM sends traces to the Langfuse instance. When absent or `false`, no tracing overhead. Hermes also supports Langfuse natively as a plugin — can be configured per-profile for targeted agent tracing.

**Auth:** `LANGFUSE_SECRET_KEY`, `LANGFUSE_PUBLIC_KEY`, `LANGFUSE_HOST` in `nizam-os.env`. Host points to the self-hosted instance (localhost or Tailscale IP).

**Bind:** `127.0.0.1` only. Accessible via Tailscale for browser UI.

**Failure mode:** If Langfuse is down and tracing is enabled, LiteLLM drops the trace silently — agent inference continues unaffected. Tracing is best-effort.

---

## Prometheus + node-exporter (internal)

**What:** Metrics collection for observability. Not external but has an integration surface.

**Why:** Three systemd timers write `.prom` textfiles for LLM spend, service health, and tool call counts. node-exporter picks these up and exposes them to Prometheus.

**Auth:** None — localhost only.

**Failure mode:** If Prometheus is down, metrics stop updating. Agents continue operating normally.

---

## Grafana (internal)

**What:** Dashboards over Prometheus metrics and PostgreSQL audit data.

**Auth:** Grafana PostgreSQL datasource connects as the `grafana` DB role (SELECT-only). Credentials set in Grafana UI, not in `nizam-os.env`.

**Failure mode:** If Grafana is down, dashboards are unavailable. No operational impact on agents or services.
