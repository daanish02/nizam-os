#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# dependencies = ["psycopg2-binary", "requests", "redis"]
# ///
"""
LLM metrics textfile writer for Prometheus node-exporter.
Runs every 60s via systemd timer. Queries LiteLLM's PostgreSQL spend logs
and writes /var/lib/prometheus/node-exporter/nizam-llm.prom.

Metrics written:
  Counters (cumulative from DB, monotonically increasing):
    nizam_llm_requests_total{model,provider,profile}
    nizam_llm_input_tokens_total{model,provider,profile}
    nizam_llm_output_tokens_total{model,provider,profile}
    nizam_llm_cache_read_tokens_total{model,profile}
    nizam_llm_cache_creation_tokens_total{model,profile}
    nizam_llm_spend_usd_total{model,provider,profile}

  Gauges (pre-aggregated for stat panels — no Prometheus math needed):
    nizam_llm_requests_today
    nizam_llm_input_tokens_today
    nizam_llm_output_tokens_today
    nizam_llm_spend_usd_today
    nizam_llm_spend_usd_this_month
    nizam_llm_cache_hit_rate_today        (0.0–1.0)
    nizam_llm_cache_savings_usd_today
    nizam_llm_avg_latency_ms_1h{model}

  Status:
    nizam_llm_proxy_up
"""

import json
import os
import re
from pathlib import Path

import psycopg2
import redis
import requests

OUT = Path("/var/lib/prometheus/node-exporter/nizam-llm.prom")
TMP = OUT.with_suffix(".prom.tmp")

_raw_db_url = os.environ.get("LITELLM_DB_URL", "")
# psycopg2 doesn't understand ?schema=... (that's Prisma/SQLAlchemy).
# Queries already fully-qualify tables as litellm."Table", so stripping is safe.
DB_URL = re.sub(r"[?&]schema=[^&]*", "", _raw_db_url).rstrip("?")
OPENROUTER_API_KEY = os.environ.get("OPENROUTER_API_KEY", "")
REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379/0")
LITELLM_URL = "http://localhost:4000"

REDIS_PRICE_KEY = "nizam:openrouter:model_prices"
REDIS_PRICE_TTL = 86400  # 24h


def get_redis() -> redis.Redis | None:
    try:
        r = redis.from_url(REDIS_URL, socket_connect_timeout=2, decode_responses=True)
        r.ping()
        return r
    except Exception:
        return None


def get_model_prices(r: redis.Redis | None) -> dict[str, dict[str, float | None]]:
    """
    Fetch per-model pricing from OpenRouter's /api/v1/models endpoint.
    Cached in Redis for 24h (TTL set by Redis, not by us).

    Returns:
      {
        "anthropic/claude-sonnet-4-6": {
          "prompt": 0.000003,       # USD per input token
          "completion": 0.000015,   # USD per output token
          "cache_read": 0.0000003,  # USD per cache-read token, or None
          "cache_creation": None,   # USD per cache-creation token, or None
        },
        ...
      }

    Provider-specific cache pricing comes directly from OpenRouter — no
    hardcoded fractions. If a model has no cache pricing in the API response,
    cache_read and cache_creation are None and savings are not estimated for it.
    """
    if r is not None:
        cached = r.get(REDIS_PRICE_KEY)
        if cached:
            try:
                return json.loads(cached)
            except Exception:
                pass

    if not OPENROUTER_API_KEY:
        return {}

    try:
        resp = requests.get(
            "https://openrouter.ai/api/v1/models",
            headers={"Authorization": f"Bearer {OPENROUTER_API_KEY}"},
            timeout=10,
        )
        resp.raise_for_status()

        prices: dict[str, dict[str, float | None]] = {}
        for model in resp.json().get("data", []):
            model_id = model.get("id", "")
            if not model_id:
                continue
            pricing = model.get("pricing", {})

            def _price(key: str) -> float | None:
                v = pricing.get(key)
                if v is None:
                    return None
                try:
                    f = float(v)
                    return f if f > 0 else None
                except (TypeError, ValueError):
                    return None

            prices[model_id] = {
                "prompt": _price("prompt"),
                "completion": _price("completion"),
                "cache_read": _price("cache_read"),
                "cache_creation": _price("cache_creation"),
            }

        if r is not None:
            try:
                r.set(REDIS_PRICE_KEY, json.dumps(prices), ex=REDIS_PRICE_TTL)
            except Exception:
                pass

        return prices
    except Exception:
        return {}


def label(**kwargs: str) -> str:
    parts = [f'{k}="{v}"' for k, v in kwargs.items() if v]
    return "{" + ",".join(parts) + "}" if parts else ""


def check_proxy_up() -> int:
    try:
        r = requests.get(f"{LITELLM_URL}/health/liveliness", timeout=3)
        return 1 if r.status_code == 200 else 0
    except Exception:
        return 0


def clean_model(raw: str) -> str:
    """Strip openrouter/ prefix added by LiteLLM routing."""
    return raw.removeprefix("openrouter/")


def provider_from_model(model: str) -> str:
    parts = model.split("/")
    return parts[0] if len(parts) >= 2 else "unknown"


def write_fallback(proxy_up: int) -> None:
    lines = [
        "# HELP nizam_llm_proxy_up LiteLLM proxy reachable (1=yes, 0=no)",
        "# TYPE nizam_llm_proxy_up gauge",
        f"nizam_llm_proxy_up {proxy_up}",
    ]
    TMP.write_text("\n".join(lines) + "\n")
    TMP.replace(OUT)


def main() -> None:
    proxy_up = check_proxy_up()

    if not DB_URL:
        write_fallback(proxy_up)
        return

    try:
        conn = psycopg2.connect(DB_URL, connect_timeout=5)
        conn.set_session(readonly=True, autocommit=True)
        cur = conn.cursor()
    except Exception:
        write_fallback(proxy_up)
        return

    r = get_redis()
    lines: list[str] = []

    def section(help_text: str, metric_type: str, name: str) -> None:
        lines.append(f"# HELP {name} {help_text}")
        lines.append(f"# TYPE {name} {metric_type}")

    # ── Proxy status ─────────────────────────────────────────────────────────
    section("LiteLLM proxy reachable (1=yes, 0=no)", "gauge", "nizam_llm_proxy_up")
    lines.append(f"nizam_llm_proxy_up {proxy_up}")

    # ── Cumulative counters by model / provider / profile ────────────────────
    try:
        cur.execute(
            """
            SELECT
                model,
                COALESCE(NULLIF(end_user, ''), 'unknown') AS profile,
                COUNT(*)                                   AS requests,
                SUM(COALESCE(prompt_tokens, 0))            AS input_tokens,
                SUM(COALESCE(completion_tokens, 0))        AS output_tokens,
                SUM(COALESCE(spend, 0.0))                  AS spend_usd,
                SUM(CASE WHEN cache_hit = 'True' THEN 1 ELSE 0 END) AS cache_hits
            FROM litellm."LiteLLM_SpendLogs"
            GROUP BY model, profile
            """
        )
        rows = cur.fetchall()
    except psycopg2.errors.UndefinedTable:
        # LiteLLM hasn't run its Prisma migration yet.
        write_fallback(proxy_up)
        conn.close()
        return
    except Exception:
        write_fallback(proxy_up)
        conn.close()
        return

    section("Cumulative LLM request count", "counter", "nizam_llm_requests_total")
    for m, profile, reqs, *_ in rows:
        m = clean_model(m)
        lines.append(f"nizam_llm_requests_total{label(model=m, provider=provider_from_model(m), profile=profile)} {reqs}")

    section("Cumulative input tokens", "counter", "nizam_llm_input_tokens_total")
    for m, profile, _, in_tok, *_ in rows:
        m = clean_model(m)
        lines.append(f"nizam_llm_input_tokens_total{label(model=m, provider=provider_from_model(m), profile=profile)} {in_tok}")

    section("Cumulative output tokens", "counter", "nizam_llm_output_tokens_total")
    for m, profile, _, _, out_tok, *_ in rows:
        m = clean_model(m)
        lines.append(f"nizam_llm_output_tokens_total{label(model=m, provider=provider_from_model(m), profile=profile)} {out_tok}")

    section("Cumulative LLM spend USD", "counter", "nizam_llm_spend_usd_total")
    for m, profile, _, _, _, spend, _ in rows:
        m = clean_model(m)
        lines.append(f"nizam_llm_spend_usd_total{label(model=m, provider=provider_from_model(m), profile=profile)} {spend:.8f}")

    # ── Cache token counters ──────────────────────────────────────────────────
    # Extracted from the response JSON stored by LiteLLM.
    # Tries multiple field paths to cover different provider formats:
    #   - cache_read_input_tokens       (Anthropic via LiteLLM normalisation)
    #   - prompt_tokens_details.cached_tokens  (OpenAI)
    # Both are provider-reported values — no assumptions about discount rates here.
    try:
        cur.execute(
            """
            SELECT
                model,
                COALESCE(NULLIF(end_user, ''), 'unknown') AS profile,
                SUM(COALESCE(
                    NULLIF((response::jsonb -> 'usage' ->> 'cache_read_input_tokens'), '')::int,
                    NULLIF((response::jsonb -> 'usage' -> 'prompt_tokens_details'
                             ->> 'cached_tokens'), '')::int,
                    0
                )) AS cache_read,
                SUM(COALESCE(
                    NULLIF((response::jsonb -> 'usage' ->> 'cache_creation_input_tokens'), '')::int,
                    0
                )) AS cache_create
            FROM litellm."LiteLLM_SpendLogs"
            WHERE response IS NOT NULL
            GROUP BY model, profile
            """
        )
        cache_rows = cur.fetchall()

        section("Cumulative cache read tokens (all providers)", "counter", "nizam_llm_cache_read_tokens_total")
        for m, profile, cache_read, _ in cache_rows:
            m = clean_model(m)
            lines.append(f"nizam_llm_cache_read_tokens_total{label(model=m, profile=profile)} {cache_read}")

        section("Cumulative cache creation tokens (all providers)", "counter", "nizam_llm_cache_creation_tokens_total")
        for m, profile, _, cache_create in cache_rows:
            m = clean_model(m)
            lines.append(f"nizam_llm_cache_creation_tokens_total{label(model=m, profile=profile)} {cache_create}")

    except Exception:
        pass

    # ── Today's gauges ────────────────────────────────────────────────────────
    try:
        cur.execute(
            """
            SELECT
                COUNT(*)                                                    AS requests,
                SUM(COALESCE(prompt_tokens, 0))                             AS input_tokens,
                SUM(COALESCE(completion_tokens, 0))                         AS output_tokens,
                SUM(COALESCE(spend, 0.0))                                   AS spend_usd,
                SUM(CASE WHEN cache_hit = 'True' THEN 1 ELSE 0 END)::float
                    / NULLIF(COUNT(*), 0)                                   AS cache_hit_rate
            FROM litellm."LiteLLM_SpendLogs"
            WHERE "startTime" >= CURRENT_DATE
            """
        )
        today = cur.fetchone()
        if today:
            req_t, in_t, out_t, spend_t, chr_t = today
            section("LLM requests today", "gauge", "nizam_llm_requests_today")
            lines.append(f"nizam_llm_requests_today {int(req_t or 0)}")
            section("Input tokens today", "gauge", "nizam_llm_input_tokens_today")
            lines.append(f"nizam_llm_input_tokens_today {int(in_t or 0)}")
            section("Output tokens today", "gauge", "nizam_llm_output_tokens_today")
            lines.append(f"nizam_llm_output_tokens_today {int(out_t or 0)}")
            section("LLM spend USD today", "gauge", "nizam_llm_spend_usd_today")
            lines.append(f"nizam_llm_spend_usd_today {float(spend_t or 0):.6f}")
            section("Cache hit rate today (0.0–1.0)", "gauge", "nizam_llm_cache_hit_rate_today")
            lines.append(f"nizam_llm_cache_hit_rate_today {float(chr_t or 0):.4f}")
    except Exception:
        pass

    # ── This month's spend ────────────────────────────────────────────────────
    try:
        cur.execute(
            """
            SELECT SUM(COALESCE(spend, 0.0))
            FROM litellm."LiteLLM_SpendLogs"
            WHERE DATE_TRUNC('month', "startTime") = DATE_TRUNC('month', NOW())
            """
        )
        row = cur.fetchone()
        section("LLM spend USD this calendar month", "gauge", "nizam_llm_spend_usd_this_month")
        lines.append(f"nizam_llm_spend_usd_this_month {float(row[0] or 0) if row else 0:.6f}")
    except Exception:
        pass

    # ── Cache savings (today) ─────────────────────────────────────────────────
    # savings per model = cache_read_tokens × (prompt_price - cache_read_price)
    # Both prices come from OpenRouter's /api/v1/models response, cached 24h in Redis.
    # No hardcoded fractions — if a model has no cache_read price in the API, it's skipped.
    try:
        cur.execute(
            """
            SELECT
                model,
                SUM(COALESCE(
                    NULLIF((response::jsonb -> 'usage' ->> 'cache_read_input_tokens'), '')::int,
                    NULLIF((response::jsonb -> 'usage' -> 'prompt_tokens_details'
                             ->> 'cached_tokens'), '')::int,
                    0
                )) AS cache_read
            FROM litellm."LiteLLM_SpendLogs"
            WHERE "startTime" >= CURRENT_DATE AND response IS NOT NULL
            GROUP BY model
            """
        )
        savings_rows = cur.fetchall() or []
        if savings_rows:
            model_prices = get_model_prices(r)
            savings = 0.0
            for m, cache_read in savings_rows:
                m_clean = clean_model(m)
                pricing = model_prices.get(m_clean) or model_prices.get(m)
                if not pricing:
                    continue
                prompt_price = pricing.get("prompt")
                cache_read_price = pricing.get("cache_read")
                # Only compute if the API returned both prices for this model
                if prompt_price is None or cache_read_price is None:
                    continue
                savings += int(cache_read or 0) * (prompt_price - cache_read_price)
            section(
                "Estimated USD saved via provider prompt cache today",
                "gauge",
                "nizam_llm_cache_savings_usd_today",
            )
            lines.append(f"nizam_llm_cache_savings_usd_today {savings:.6f}")
    except Exception:
        pass

    # ── Avg latency by model (last 1h) ────────────────────────────────────────
    try:
        cur.execute(
            """
            SELECT
                model,
                AVG(EXTRACT(EPOCH FROM ("endTime" - "startTime")) * 1000) AS avg_ms
            FROM litellm."LiteLLM_SpendLogs"
            WHERE "startTime" > NOW() - INTERVAL '1 hour'
              AND "endTime" IS NOT NULL
            GROUP BY model
            """
        )
        latency_rows = cur.fetchall()
        if latency_rows:
            section(
                "Average LLM response latency ms over last 1h by model",
                "gauge",
                "nizam_llm_avg_latency_ms_1h",
            )
            for m, avg_ms in latency_rows:
                m = clean_model(m)
                lines.append(f'nizam_llm_avg_latency_ms_1h{{model="{m}"}} {float(avg_ms or 0):.1f}')
    except Exception:
        pass

    conn.close()

    TMP.write_text("\n".join(lines) + "\n")
    TMP.replace(OUT)
    OUT.chmod(0o644)


if __name__ == "__main__":
    main()
