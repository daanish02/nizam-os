# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Toolchain preflight — refuses to scaffold with a missing or wrong-version tool.

The scaffold scripts install real toolchains and frameworks. Before this gate
they checked nothing: `nextjs-frontend.sh` ran `create-next-app@latest` against
a documented pin of ~15.3.0 and a live run installed Next 16.3.4, which is then
days of code written against the wrong API. A missing tool failed halfway
through, leaving a half-written tree.

So: check every required tool is present and in range BEFORE anything is
written, and say exactly what to install and where when it is not.

Version data comes from conventions/versions.toml — never hardcoded here, so
the pin and the check cannot drift apart.

Usage:
  uv run feanor/scripts/check-toolchain.py uv python        # python scaffold
  uv run feanor/scripts/check-toolchain.py bun              # frontend scaffold
  uv run feanor/scripts/check-toolchain.py go
  uv run feanor/scripts/check-toolchain.py --list
  uv run feanor/scripts/check-toolchain.py bun --override "bun 1.4 known-good here"

Exits 0 when every named tool is present and in range, 1 naming what to fix.
"""

import argparse
import re
import subprocess
import sys
import tomllib
from pathlib import Path

from _gate import add_override_arg, finish

VERSIONS = Path(__file__).resolve().parent.parent / "conventions" / "versions.toml"


def load_versions() -> dict:
    try:
        return tomllib.loads(VERSIONS.read_text(encoding="utf-8"))
    except (OSError, tomllib.TOMLDecodeError) as exc:
        print(f"cannot read {VERSIONS}: {exc}", file=sys.stderr)
        sys.exit(1)


def parse_version(text: str) -> tuple[int, ...]:
    return tuple(int(part) for part in text.split("."))


def satisfies(version: str, spec: str) -> bool:
    """Check a version against a comma-separated range like '>=1.3.0,<1.4.0'."""
    actual = parse_version(version)
    for clause in spec.split(","):
        clause = clause.strip()
        match = re.match(r"^(>=|<=|>|<|==)\s*(\d+(?:\.\d+)*)$", clause)
        if not match:
            return False
        op, raw = match.groups()
        want = parse_version(raw)
        # Compare on the shorter tuple's length so ">=3.12" accepts 3.12.7.
        left, right = actual[: len(want)], want
        if op == ">=" and not left >= right:
            return False
        if op == "<=" and not left <= right:
            return False
        if op == ">" and not left > right:
            return False
        if op == "<" and not actual < want:
            return False
        if op == "==" and left != right:
            return False
    return True


def installed_version(tool: str, spec: dict) -> tuple[str | None, str | None]:
    """Returns (version, error). Version is None when the tool is unusable."""
    argv = spec["check"].split()
    try:
        proc = subprocess.run(argv, capture_output=True, text=True, timeout=30)
    except FileNotFoundError:
        return None, "not installed"
    except OSError as exc:
        return None, f"could not run {spec['check']!r}: {exc}"
    except subprocess.TimeoutExpired:
        return None, f"{spec['check']!r} timed out"

    output = proc.stdout + proc.stderr
    match = re.search(spec["extract"], output)
    if not match:
        return None, f"could not read a version from {spec['check']!r} output"
    return match.group(1), None


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("tools", nargs="*", help="tool names from versions.toml")
    parser.add_argument("--list", action="store_true", help="list known tools and pins")
    parser.add_argument("--pin", metavar="FRAMEWORK", help="print a framework's pin and exit")
    parser.add_argument(
        "--verify-range", metavar="FRAMEWORK", help="print a framework's verify range and exit"
    )
    parser.add_argument(
        "--satisfies",
        nargs=2,
        metavar=("VERSION", "RANGE"),
        help="exit 0 if VERSION is within RANGE, 1 otherwise",
    )
    add_override_arg(parser)
    args = parser.parse_args()

    data = load_versions()
    known = data.get("tools", {})
    frameworks = data.get("frameworks", {})

    # Lookup modes exist so the shell scripts never parse TOML themselves —
    # one reader, and no path conversion (Git Bash hands out POSIX paths the
    # Windows Python binary cannot open).
    if args.satisfies:
        sys.exit(0 if satisfies(*args.satisfies) else 1)

    for flag, key in (("pin", "pin"), ("verify_range", "verify")):
        name = getattr(args, flag)
        if name:
            entry = frameworks.get(name)
            if entry is None or key not in entry:
                print(f"{name}: no {key!r} in {VERSIONS.name}", file=sys.stderr)
                sys.exit(1)
            print(entry[key])
            sys.exit(0)

    if args.list:
        for name, spec in known.items():
            print(f"{name:10} {spec['range']:20} {spec.get('rationale', '')}")
        for name, spec in frameworks.items():
            print(f"{name:10} {spec.get('pin', ''):20} {spec.get('rationale', '')}")
        sys.exit(0)

    if not args.tools:
        parser.error("name at least one tool, or pass --list")

    failures: list[str] = []
    for tool in args.tools:
        spec = known.get(tool)
        if spec is None:
            failures.append(f"{tool}: not declared in {VERSIONS.name}")
            continue

        version, error = installed_version(tool, spec)
        if version is None:
            failures.append(
                f"{tool} {error} — need {spec['range']}\n"
                f"        Install: {spec['install']}"
            )
            continue

        if not satisfies(version, spec["range"]):
            failures.append(
                f"{tool} {version} is outside {spec['range']}\n"
                f"        {spec.get('rationale', '')}\n"
                f"        Install: {spec['install']}"
            )
            continue

        print(f"OK    {tool} {version}  ({spec['range']})")

    finish(
        "toolchain preflight",
        failures,
        override=args.override,
        ok_message=f"OK — {len(args.tools)} tool(s) present and in range.",
    )


if __name__ == "__main__":
    main()
