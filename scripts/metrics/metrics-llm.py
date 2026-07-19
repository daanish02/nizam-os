#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# dependencies = ["requests", "redis"]
# ///
"""
LLM metrics textfile writer for Prometheus node-exporter.
Reads LiteLLM /spend/logs every 60s (systemd timer); writes /var/lib/prometheus/node-exporter/nizam-llm.prom.
Prefixes: nizam_llm_{requests,input_tokens,output_tokens,spend_usd,cache_read_tokens,cache_creation_tokens}_total
  | nizam_llm_{requests,input_tokens,output_tokens,spend_usd}_today | nizam_llm_{spend_usd_this_month,cache_hit_rate_today,cache_savings_usd_today,cache_savings_usd_total,avg_latency_ms_1h,proxy_up}
"""

import json
import logging
import os
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path

import redis
import requests


sys.path.insert(0, str(Path(__file__).parent.parent / "shared"))
from _log import setup_logging  # noqa: E402

log = setup_logging("metrics-llm")

OUT = Path("/var/lib/prometheus/node-exporter/nizam-llm.prom")
TMP = OUT.with_suffix(".prom.tmp")

LITELLM_URL = "http://localhost:4000"
LITELLM_KEY = os.environ.get("LITELLM_MASTER_KEY", "")
OPENROUTER_API_KEY = os.environ.get("OPENROUTER_API_KEY", "")
REDIS_URL = os.environ.get("REDIS_URL", "redis://localhost:6379/0")

REDIS_PRICE_KEY = "nizam:openrouter:model_prices"
REDIS_PRICE_TTL = 86400  # 24h


def get_redis() -> redis.Redis | None:
    try:
        r = redis.from_url(REDIS_URL, socket_connect_timeout=2, decode_responses=True)
        r.ping()
        return r
    except Exception:
        return None


def get_model_prices(r: redis.Redis | None) -> dict:
    """Fetch per-model USD prices from Redis cache, falling back to OpenRouter API."""
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

        prices: dict = {}
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
    while raw.startswith("openrouter/"):
        raw = raw[len("openrouter/"):]
    return raw


def provider_from_model(model: str) -> str:
    parts = model.split("/")
    return parts[0] if len(parts) >= 2 else "unknown"


def parse_time(ts: str | None) -> datetime | None:
    if not ts:
        return None
    try:
        return datetime.fromisoformat(ts.rstrip("Z")).replace(tzinfo=timezone.utc)
    except Exception:
        return None


def write_fallback(proxy_up: int) -> None:
    lines = [
        "# HELP nizam_llm_proxy_up LiteLLM proxy reachable (1=yes, 0=no)",
        "# TYPE nizam_llm_proxy_up gauge",
        f"nizam_llm_proxy_up {proxy_up}",
    ]
    TMP.write_text("\n".join(lines) + "\n")
    TMP.replace(OUT)
    log.warning("proxy_up=%d — wrote fallback only (no spend data)", proxy_up)


def fetch_logs() -> list | None:
    """Query LiteLLM DB for request rows in the last N minutes. Returns list of dicts."""
    if not LITELLM_KEY:
        log.error("LITELLM_MASTER_KEY not set — cannot fetch spend logs")
        return None
    try:
        resp = requests.get(
            f"{LITELLM_URL}/spend/logs",
            params={"limit": 10000},
            headers={"Authorization": f"Bearer {LITELLM_KEY}"},
            timeout=15,
        )
        resp.raise_for_status()
        data = resp.json()
        log.info("fetched %d spend log entries", len(data))
        return data
    except Exception as e:
        log.error("fetch_logs failed: %s", e)
        return None


def main() -> None:
    proxy_up = check_proxy_up()

    logs = fetch_logs()
    if logs is None:
        write_fallback(proxy_up)
        return

    now = datetime.now(timezone.utc)
    today_date = now.date()
    month_start = today_date.replace(day=1)
    one_hour_ago = now.timestamp() - 3600

    r = get_redis()
    model_prices = get_model_prices(r)
    lines: list[str] = []

    def section(help_text: str, metric_type: str, name: str) -> None:
        lines.append(f"# HELP {name} {help_text}")
        lines.append(f"# TYPE {name} {metric_type}")

    # Accumulate per-series totals
    totals: dict = defaultdict(lambda: {
        "requests": 0, "input_tokens": 0, "output_tokens": 0,
        "spend": 0.0, "cache_read": 0, "cache_create": 0,
    })

    today_req = today_in = today_out = 0
    today_spend = 0.0
    today_cache_hits = 0
    month_spend = 0.0
    latency_by_model: dict = defaultdict(list)
    today_cache_read_by_model: dict = defaultdict(int)

    for entry in logs:
        model = entry.get("model", "") or ""
        profile = entry.get("user", "") or "unknown"
        in_tok = int(entry.get("prompt_tokens") or 0)
        out_tok = int(entry.get("completion_tokens") or 0)

        litellm_spend = float(entry.get("spend") or 0)
        if litellm_spend == 0.0 and (in_tok or out_tok):
            mc = clean_model(model)
            pricing = model_prices.get(mc) or model_prices.get(model)
            if pricing:
                spend = in_tok * (pricing.get("prompt") or 0.0) + out_tok * (pricing.get("completion") or 0.0)
            else:
                spend = 0.0
        else:
            spend = litellm_spend

        # Cache tokens: try metadata.usage_object (OpenAI format) then response.usage (Anthropic)
        meta = entry.get("metadata") or {}
        usage_obj = meta.get("usage_object") or {}
        ptd = usage_obj.get("prompt_tokens_details") or {}
        cache_read = int(ptd.get("cached_tokens") or 0)
        cache_create = int(ptd.get("cache_write_tokens") or 0)

        key = (model, profile)
        totals[key]["requests"] += 1
        totals[key]["input_tokens"] += in_tok
        totals[key]["output_tokens"] += out_tok
        totals[key]["spend"] += spend
        totals[key]["cache_read"] += cache_read
        totals[key]["cache_create"] += cache_create

        start_ts = parse_time(entry.get("startTime"))
        end_ts = parse_time(entry.get("endTime"))

        if start_ts:
            start_date = start_ts.date()

            if start_date == today_date:
                today_req += 1
                today_in += in_tok
                today_out += out_tok
                today_spend += spend
                if cache_read > 0:
                    today_cache_hits += 1
                today_cache_read_by_model[model] += cache_read

            if start_date >= month_start:
                month_spend += spend

            if start_ts.timestamp() >= one_hour_ago:
                dur = entry.get("request_duration_ms")
                if dur is None and end_ts:
                    dur = (end_ts.timestamp() - start_ts.timestamp()) * 1000
                if dur is not None:
                    latency_by_model[clean_model(model)].append(float(dur))

    # Proxy status
    section("LiteLLM proxy reachable (1=yes, 0=no)", "gauge", "nizam_llm_proxy_up")
    lines.append(f"nizam_llm_proxy_up {proxy_up}")

    # Cumulative counters
    section("Cumulative LLM request count", "counter", "nizam_llm_requests_total")
    for (m, profile), v in totals.items():
        mc = clean_model(m)
        lines.append(f"nizam_llm_requests_total{label(model=mc, provider=provider_from_model(mc), profile=profile)} {v['requests']}")

    section("Cumulative input tokens", "counter", "nizam_llm_input_tokens_total")
    for (m, profile), v in totals.items():
        mc = clean_model(m)
        lines.append(f"nizam_llm_input_tokens_total{label(model=mc, provider=provider_from_model(mc), profile=profile)} {v['input_tokens']}")

    section("Cumulative output tokens", "counter", "nizam_llm_output_tokens_total")
    for (m, profile), v in totals.items():
        mc = clean_model(m)
        lines.append(f"nizam_llm_output_tokens_total{label(model=mc, provider=provider_from_model(mc), profile=profile)} {v['output_tokens']}")

    section("Cumulative LLM spend USD", "counter", "nizam_llm_spend_usd_total")
    for (m, profile), v in totals.items():
        mc = clean_model(m)
        lines.append(f"nizam_llm_spend_usd_total{label(model=mc, provider=provider_from_model(mc), profile=profile)} {v['spend']:.8f}")

    section("Cumulative cache read tokens", "counter", "nizam_llm_cache_read_tokens_total")
    for (m, profile), v in totals.items():
        mc = clean_model(m)
        lines.append(f"nizam_llm_cache_read_tokens_total{label(model=mc, profile=profile)} {v['cache_read']}")

    section("Cumulative cache creation tokens", "counter", "nizam_llm_cache_creation_tokens_total")
    for (m, profile), v in totals.items():
        mc = clean_model(m)
        lines.append(f"nizam_llm_cache_creation_tokens_total{label(model=mc, profile=profile)} {v['cache_create']}")

    # Today's gauges
    section("LLM requests today", "gauge", "nizam_llm_requests_today")
    lines.append(f"nizam_llm_requests_today {today_req}")

    section("Input tokens today", "gauge", "nizam_llm_input_tokens_today")
    lines.append(f"nizam_llm_input_tokens_today {today_in}")

    section("Output tokens today", "gauge", "nizam_llm_output_tokens_today")
    lines.append(f"nizam_llm_output_tokens_today {today_out}")

    section("LLM spend USD today", "gauge", "nizam_llm_spend_usd_today")
    lines.append(f"nizam_llm_spend_usd_today {today_spend:.6f}")

    section("Cache hit rate today (0.0–1.0)", "gauge", "nizam_llm_cache_hit_rate_today")
    chr_val = (today_cache_hits / today_req) if today_req > 0 else 0.0
    lines.append(f"nizam_llm_cache_hit_rate_today {chr_val:.4f}")

    # Month spend 
    section("LLM spend USD this calendar month", "gauge", "nizam_llm_spend_usd_this_month")
    lines.append(f"nizam_llm_spend_usd_this_month {month_spend:.6f}")

    # Cache savings (today + all time)
    all_cache_read_by_model: dict = defaultdict(int)
    for (m, _profile), v in totals.items():
        all_cache_read_by_model[m] += v["cache_read"]

    def _calc_savings(cache_by_model: dict) -> float:
        """Return (tokens_saved: int, usd_saved: float) from cache hit counts."""
        s = 0.0
        for m, cr in cache_by_model.items():
            mc = clean_model(m)
            pricing = model_prices.get(mc) or model_prices.get(m)
            if not pricing:
                continue
            prompt_price = pricing.get("prompt")
            cache_read_price = pricing.get("cache_read")
            if prompt_price is not None and cache_read_price is not None:
                s += cr * (prompt_price - cache_read_price)
        return s

    section("Estimated USD saved via provider prompt cache today", "gauge", "nizam_llm_cache_savings_usd_today")
    lines.append(f"nizam_llm_cache_savings_usd_today {_calc_savings(today_cache_read_by_model):.6f}")

    section("Estimated USD saved via provider prompt cache all time", "gauge", "nizam_llm_cache_savings_usd_total")
    lines.append(f"nizam_llm_cache_savings_usd_total {_calc_savings(all_cache_read_by_model):.6f}")

    # Avg latency by model (last 1h) 
    if latency_by_model:
        section("Average LLM response latency ms over last 1h by model", "gauge", "nizam_llm_avg_latency_ms_1h")
        for m, durations in latency_by_model.items():
            avg_ms = sum(durations) / len(durations)
            lines.append(f'nizam_llm_avg_latency_ms_1h{{model="{m}"}} {avg_ms:.1f}')

    TMP.write_text("\n".join(lines) + "\n")
    TMP.replace(OUT)
    OUT.chmod(0o644)
    log.info(
        "wrote %d series, today: %d req / %d+%d tok / $%.4f, month: $%.4f",
        len(totals), today_req, today_in, today_out, today_spend, month_spend,
    )


if __name__ == "__main__":
    main()
