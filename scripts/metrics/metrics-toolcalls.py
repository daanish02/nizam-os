#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""
Tool call metrics textfile writer for Prometheus node-exporter.
Runs every 5 min via systemd timer. Parses Hermes agent.log files across
all profiles (including rotated .1/.2/.3), counts tool calls, and writes:
  /var/lib/prometheus/node-exporter/nizam-toolcalls.prom

Metrics written:
  nizam_tool_calls_total{profile, tool}            — all calls in retained logs
  nizam_tool_errors_total{profile, tool}           — error calls
  nizam_tool_calls_today{profile, tool}            — calls since midnight UTC
  nizam_tool_duration_seconds_total{profile, tool} — cumulative wall time
"""

import logging
import re
import sys
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path


sys.path.insert(0, str(Path(__file__).parent.parent / "shared"))
from _log import setup_logging  # noqa: E402

log = setup_logging("metrics-toolcalls")

HERMES_PROFILES = Path.home() / ".hermes" / "profiles"
OUT = Path("/var/lib/prometheus/node-exporter/nizam-toolcalls.prom")
TMP = OUT.with_suffix(".prom.tmp")

_RE_TOOL = re.compile(
    r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}),\d+"
    r".*?agent\.tool_executor: [Tt]ool ([\w]+) "
    r"(completed|returned error)"
    r".*?\((\d+(?:\.\d+)?)s"
    r"(?:,\s*(\d+)\s*chars)?"
)


def parse_ts(ts_str: str) -> datetime | None:
    try:
        return datetime.strptime(ts_str, "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
    except Exception:
        return None


def main() -> None:
    now = datetime.now(timezone.utc)
    today_midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)

    counts: dict = defaultdict(lambda: defaultdict(lambda: {"calls": 0, "errors": 0, "duration_s": 0.0, "chars": 0}))
    today: dict = defaultdict(lambda: defaultdict(lambda: {"calls": 0, "chars": 0}))

    for profile_dir in sorted(HERMES_PROFILES.iterdir()):
        if not profile_dir.is_dir():
            continue
        profile = profile_dir.name
        agent_log = profile_dir / "logs" / "agent.log"
        if not agent_log.exists():
            continue

        candidates = sorted(
            agent_log.parent.glob(agent_log.name + "*"),
            key=lambda p: p.stat().st_mtime,
        )

        for path in candidates:
            if not path.is_file():
                continue
            try:
                for line in path.read_text(errors="replace").splitlines():
                    m = _RE_TOOL.match(line)
                    if not m:
                        continue
                    ts = parse_ts(m.group(1))
                    if ts is None:
                        continue
                    tool = m.group(2)
                    is_error = m.group(3) == "returned error"
                    duration_s = float(m.group(4))
                    chars = int(m.group(5)) if m.group(5) else 0
                    counts[profile][tool]["calls"] += 1
                    counts[profile][tool]["duration_s"] += duration_s
                    counts[profile][tool]["chars"] += chars
                    if is_error:
                        counts[profile][tool]["errors"] += 1
                    if ts >= today_midnight:
                        today[profile][tool]["calls"] += 1
                        today[profile][tool]["chars"] += chars
            except Exception as e:
                log.warning("failed reading %s: %s", path, e)

    lines: list[str] = []

    def section(help_text: str, metric_type: str, name: str) -> None:
        lines.append(f"# HELP {name} {help_text}")
        lines.append(f"# TYPE {name} {metric_type}")

    section("Hermes tool calls across retained logs by profile and tool", "counter", "nizam_tool_calls_total")
    for profile, tools in sorted(counts.items()):
        for tool, v in sorted(tools.items()):
            lines.append(f'nizam_tool_calls_total{{profile="{profile}",tool="{tool}"}} {v["calls"]}')

    section("Hermes tool errors across retained logs by profile and tool", "counter", "nizam_tool_errors_total")
    for profile, tools in sorted(counts.items()):
        for tool, v in sorted(tools.items()):
            if v["errors"] > 0:
                lines.append(f'nizam_tool_errors_total{{profile="{profile}",tool="{tool}"}} {v["errors"]}')

    section("Hermes tool wall time seconds across retained logs by profile and tool", "counter", "nizam_tool_duration_seconds_total")
    for profile, tools in sorted(counts.items()):
        for tool, v in sorted(tools.items()):
            lines.append(f'nizam_tool_duration_seconds_total{{profile="{profile}",tool="{tool}"}} {v["duration_s"]:.3f}')

    section("Hermes tool output chars across retained logs by profile and tool", "counter", "nizam_tool_output_chars_total")
    for profile, tools in sorted(counts.items()):
        for tool, v in sorted(tools.items()):
            lines.append(f'nizam_tool_output_chars_total{{profile="{profile}",tool="{tool}"}} {v["chars"]}')

    section("Hermes tool calls since midnight UTC by profile and tool", "gauge", "nizam_tool_calls_today")
    for profile, tools in sorted(today.items()):
        for tool, v in sorted(tools.items()):
            lines.append(f'nizam_tool_calls_today{{profile="{profile}",tool="{tool}"}} {v["calls"]}')

    section("Hermes tool output chars since midnight UTC by profile and tool", "gauge", "nizam_tool_output_chars_today")
    for profile, tools in sorted(today.items()):
        for tool, v in sorted(tools.items()):
            lines.append(f'nizam_tool_output_chars_today{{profile="{profile}",tool="{tool}"}} {v["chars"]}')

    TMP.write_text("\n".join(lines) + "\n")
    TMP.replace(OUT)
    OUT.chmod(0o644)

    total_series = sum(len(t) for t in counts.values())
    log.info("wrote %d series across %d profiles", total_series, len(counts))


if __name__ == "__main__":
    main()
