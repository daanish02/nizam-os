# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Runs the project's own CI checks locally, before a push.

In a live run, lint and build failures were discovered only after pushing —
the history carries fixup commits like "fix(frontend): fix biome import order"
and "fix(frontend): replace nonexistent LayoutProps". Both are caught by
running the same checks locally first. CI is the backstop, not the first
place to find out.

Commands are derived from what is actually on disk, the same way
scaffold/write-dev-scripts.sh discovers services — a separate hardcoded list
would drift from the project the moment its stack changed. Override the
derived set by writing .feanor/state/local-ci.json:

    {"commands": [["bun", "run", "lint"], ["uv", "run", "pytest", "-m", "not slow"]]}

Each command runs without a shell (no injection surface, per
cross-stack/untrusted-input.md) and its real exit code is recorded — never a
pipeline's, which is the bug plan.py verify already exists to avoid.

Usage (from project root):
  uv run feanor/scripts/check-push.py
  uv run feanor/scripts/check-push.py --list        # show what would run
  uv run feanor/scripts/check-push.py --override "docs-only change"
"""

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from _gate import add_override_arg, finish

LOG_PATH = Path(".feanor/logs/validation.log")
MANIFEST = Path(".feanor/state/local-ci.json")


def python_dirs() -> list[Path]:
    roots = [Path("backend"), *sorted(Path("services").glob("*"))]
    return [d for d in roots if (d / "pyproject.toml").is_file()]


def frontend_dirs() -> list[Path]:
    return [d for d in [Path("frontend")] if (d / "package.json").is_file()]


def derive_commands() -> list[tuple[Path, list[str]]]:
    """What to run, inferred from the stacks actually present."""
    jobs: list[tuple[Path, list[str]]] = []

    for directory in python_dirs():
        jobs.append((directory, ["uv", "run", "ruff", "check", "."]))
        jobs.append((directory, ["uv", "run", "pytest", "-m", "not slow", "-q"]))

    for directory in frontend_dirs():
        # Lint and typecheck catch the two failure classes seen post-push:
        # import ordering and a type that does not exist.
        jobs.append((directory, ["bun", "run", "lint"]))
        jobs.append((directory, ["bunx", "tsc", "--noEmit"]))

    return jobs


def manifest_commands() -> list[tuple[Path, list[str]]] | None:
    if not MANIFEST.is_file():
        return None
    try:
        data = json.loads(MANIFEST.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        print(f"{MANIFEST} is unreadable ({exc}) — falling back to derived commands.", file=sys.stderr)
        return None

    jobs: list[tuple[Path, list[str]]] = []
    for entry in data.get("commands", []):
        if isinstance(entry, dict):
            jobs.append((Path(entry.get("cwd", ".")), list(entry["command"])))
        else:
            jobs.append((Path("."), list(entry)))
    return jobs or None


def run(directory: Path, argv: list[str]) -> tuple[int, str]:
    try:
        proc = subprocess.run(argv, cwd=directory, capture_output=True, text=True)
        return proc.returncode, proc.stdout + proc.stderr
    except OSError as exc:
        return 127, f"failed to execute {argv[0]!r}: {exc}\n"


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--list", action="store_true", help="print the commands and exit")
    add_override_arg(parser)
    args = parser.parse_args()

    jobs = manifest_commands() or derive_commands()

    if args.list:
        for directory, argv in jobs:
            print(f"{directory}: {' '.join(argv)}")
        sys.exit(0)

    if not jobs:
        print("No Python or frontend project found — nothing to check.")
        sys.exit(0)

    failures: list[str] = []
    LOG_PATH.parent.mkdir(parents=True, exist_ok=True)

    for directory, argv in jobs:
        printable = " ".join(argv)
        if not directory.is_dir():
            continue
        # ASCII only: Windows consoles default to cp1252, which cannot encode
        # box-drawing characters and raises UnicodeEncodeError mid-run.
        print(f"-- {directory}: {printable}")
        exit_code, output = run(directory, argv)

        with LOG_PATH.open("a", encoding="utf-8") as log:
            log.write(f"\n=== pre-push @ {datetime.now(timezone.utc).isoformat()} ===\n")
            log.write(f"$ {printable}   (cwd={directory})\n")
            log.write(output)
            log.write(f"exit_code={exit_code}\n")

        if exit_code != 0:
            sys.stdout.write(output)
            failures.append(
                f"{printable} failed in {directory} (exit {exit_code}) — "
                f"full output in {LOG_PATH}"
            )

    finish(
        "pre-push local checks",
        failures,
        override=args.override,
        ok_message=f"OK — {len(jobs)} local check(s) passed. Safe to push.",
    )


if __name__ == "__main__":
    main()
