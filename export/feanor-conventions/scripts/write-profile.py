# /// script
# requires-python = ">=3.12"
# dependencies = ["tomlkit"]
# ///
"""Write .feanor/profile.toml — the project's capability profile.

Called by agents/architect-agent.md during /hld, after conditional triggers are
derived from the architecture and optional capabilities are chosen with the user.

Usage (from project root):
  uv run feanor/scripts/write-profile.py --api --database postgresql --auth --metrics
  uv run feanor/scripts/write-profile.py --show          # print the resolved profile
  uv run feanor/scripts/write-profile.py --check <tag>   # exit 0 if that capability is enabled

Three tiers, per feanor/docs/CAPABILITIES.md:
  baseline    - always on, never recorded here, no flag exists
  conditional - mandatory when a structural trigger holds (--api, --database, ...)
  optional    - opt-in per project (--metrics, --tracing, --caching, ...)

The file is read by meta/context-resolver.md, agents/planner-agent.md, and
agents/validation-agent.md. A capability absent here is never loaded, never
ticketed, and never reported as missing.
"""

import argparse
import sys
from pathlib import Path

try:
    import tomlkit
except ModuleNotFoundError:
    from _gate import require_uv_run

    require_uv_run("tomlkit")

PROFILE_PATH = Path(".feanor/profile.toml")

# Conditional triggers: flag -> conventions that become mandatory when true.
CONDITIONAL = {
    "api": ["cross-stack/api-design.md", "cross-stack/middleware.md", "cross-stack/health-endpoints.md"],
    "auth": ["cross-stack/auth.md"],
    "personal_data": ["cross-stack/data-protection.md"],
    "multi_tenant": ["cross-stack/access-control.md", "cross-stack/database.md"],
    "public_internet": ["cross-stack/rate-limiting.md"],
    "concurrency": ["go/concurrency-context.md", "python/async-concurrency.md"],
    "long_running_service": ["cross-stack/health-endpoints.md"],
}

# Optional capabilities: flag -> convention. None means "no convention written yet",
# and those must not be offered — there would be nothing for /exec to load.
OPTIONAL = {
    "metrics": "cross-stack/metrics.md",
    "tracing": "cross-stack/tracing.md",
    "caching": "cross-stack/caching.md",
    "issue_reporting": "cross-stack/issue-reporting.md",
    "feature_flags": None,
    "background_jobs": None,
    "search": None,
    "i18n": None,
}

DIALECTS = {"postgresql", "mysql", "mariadb", "sqlserver", "oracle", "sqlite"}

HEADER = """\
# Feanor capability profile — written by /hld, read by /exec, /plan and /audit.
#
# Baseline conventions are NOT listed here: they always apply and have no toggle.
# See feanor/docs/CAPABILITIES.md for the three-tier model.
#
# [conditional] is derived from the architecture, not chosen. If the system has
# an API, api-design applies; that is a consequence, not a preference.
#
# [optional] is chosen per project. A capability set false is never loaded by the
# Context Resolver, never ticketed by the Planner, and never reported missing by
# the Validation Agent.
"""


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--api", action="store_true", help="exposes an HTTP API")
    p.add_argument("--database", metavar="DIALECT", help=f"relational database in use ({'|'.join(sorted(DIALECTS))})")
    p.add_argument("--auth", action="store_true", help="has authenticated users")
    p.add_argument("--personal-data", action="store_true", help="stores personal or regulated data")
    p.add_argument("--multi-tenant", action="store_true", help="serves multiple tenants")
    p.add_argument("--public-internet", action="store_true", help="reachable from the public internet")
    p.add_argument("--concurrency", action="store_true", help="uses goroutines / async concurrency")
    p.add_argument("--long-running-service", action="store_true", help="deployed as a long-running service")
    for name, convention in OPTIONAL.items():
        flag = "--" + name.replace("_", "-")
        note = "" if convention else "  [NO CONVENTION YET — do not enable]"
        p.add_argument(flag, action="store_true", help=f"enable {name}{note}")
    p.add_argument("--show", action="store_true", help="print the current profile and exit")
    p.add_argument("--check", metavar="CAPABILITY", help="exit 0 if enabled, 1 if not")
    return p


def load_profile() -> tomlkit.TOMLDocument | None:
    if not PROFILE_PATH.exists():
        return None
    return tomlkit.parse(PROFILE_PATH.read_text(encoding="utf-8"))


def cmd_show() -> None:
    doc = load_profile()
    if doc is None:
        print(f"No profile at {PROFILE_PATH} — run /hld, or write one with this script.")
        sys.exit(1)
    conditional = doc.get("conditional", {})
    optional = doc.get("optional", {})

    print("Baseline: always applied (coding-principles, tdd, security set, logging, git, ...)\n")
    print("Conditional (derived from architecture):")
    for key, value in conditional.items():
        if value:
            extra = ", ".join(CONDITIONAL.get(key, [])) if key in CONDITIONAL else ""
            print(f"  {key} = {value!r}" + (f"  -> {extra}" if extra else ""))
    print("\nOptional (chosen):")
    for key, value in optional.items():
        mark = "on " if value else "off"
        print(f"  [{mark}] {key}")


def cmd_check(capability: str) -> None:
    doc = load_profile()
    if doc is None:
        sys.exit(1)
    for section in ("conditional", "optional"):
        value = doc.get(section, {}).get(capability)
        if value:
            sys.exit(0)
    sys.exit(1)


def main() -> None:
    args = build_parser().parse_args()

    if args.show:
        cmd_show()
        return
    if args.check:
        cmd_check(args.check)
        return

    if args.database and args.database not in DIALECTS:
        print(f"Unknown dialect {args.database!r}. Expected one of: {', '.join(sorted(DIALECTS))}")
        sys.exit(1)

    enabled_without_convention = [
        name for name in OPTIONAL
        if getattr(args, name, False) and OPTIONAL[name] is None
    ]
    if enabled_without_convention:
        # Enabling one of these would leave /exec with nothing to load, so the
        # implementation would be improvised rather than governed.
        print("Refusing to enable capabilities that have no convention file yet:")
        for name in enabled_without_convention:
            print(f"  {name}")
        print("Write the convention first (workflows/maintain-repo.md section 3), then enable it.")
        sys.exit(1)

    doc = tomlkit.parse(HEADER)

    conditional = tomlkit.table()
    conditional["api"] = args.api
    conditional["database"] = args.database or False
    conditional["auth"] = args.auth
    conditional["personal_data"] = args.personal_data
    conditional["multi_tenant"] = args.multi_tenant
    conditional["public_internet"] = args.public_internet
    conditional["concurrency"] = args.concurrency
    conditional["long_running_service"] = args.long_running_service
    doc["conditional"] = conditional

    optional = tomlkit.table()
    for name in OPTIONAL:
        optional[name] = bool(getattr(args, name, False))
    doc["optional"] = optional

    PROFILE_PATH.parent.mkdir(parents=True, exist_ok=True)
    PROFILE_PATH.write_text(tomlkit.dumps(doc), encoding="utf-8")

    print(f"Wrote {PROFILE_PATH}")
    security_docs_required = any([
        args.auth, args.personal_data, args.multi_tenant,
        args.public_internet, args.api,
    ])
    if security_docs_required:
        print("  docs/SECURITY.md and docs/THREAT-MODEL.md are MANDATORY for this profile.")
    print("  Baseline conventions always apply and are not listed in the file.")


if __name__ == "__main__":
    main()
