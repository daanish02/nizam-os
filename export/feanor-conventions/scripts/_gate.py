"""Shared gate behaviour for Feanor's check scripts.

A gate refuses the action when a mechanical check fails. Every gate accepts
`--override "<reason>"`, which proceeds anyway and records the reason in
.feanor/logs/overrides.log.

The override exists because a wrong check must never be able to halt real work
permanently — but it is deliberate and leaves a trail, so bypassing is a
decision someone made rather than a step quietly skipped. That is the whole
difference between a gate and a suggestion.

Imported by sibling scripts in this directory; `uv run` puts the script's own
directory on sys.path, so a plain `from _gate import ...` resolves. No
third-party dependencies, so it adds nothing to any script's PEP 723 block.
"""

from __future__ import annotations

import sys
from datetime import datetime, timezone
from pathlib import Path

OVERRIDE_LOG = Path(".feanor/logs/overrides.log")


def require_uv_run(module_names: str) -> None:
    """Explain the real problem when a PEP 723 script is run with bare python.

    These scripts declare their dependencies inline and are meant to be run as
    `uv run <script>`, which installs them for that run only. Run with a bare
    interpreter they raise ModuleNotFoundError — a traceback that reads like a
    broken script, and whose obvious "fix" is `pip install`. That abandons uv,
    pollutes whatever environment happened to be active, and makes the next run
    depend on machine state instead of on the script's own header. It has
    happened in a real run. Refuse instead, and name the one command that works.

    Exits 2, not 1, so environment misuse is distinguishable from a gate failure.
    """
    script = Path(sys.argv[0]).name
    args = " ".join(sys.argv[1:])
    print(
        f"{script} needs its inline (PEP 723) dependencies: {module_names}.\n"
        f"\n"
        f"Run it with uv, which installs them for this run only:\n"
        f"    uv run feanor/scripts/{script}{' ' + args if args else ''}\n"
        f"\n"
        f"Do NOT `pip install` these. The dependency list lives in this script's\n"
        f"own `# /// script` header; installing them globally makes the next run\n"
        f"depend on machine state rather than on that header.",
        file=sys.stderr,
    )
    sys.exit(2)


def add_override_arg(parser) -> None:
    """Register the standard --override flag on an argparse parser."""
    parser.add_argument(
        "--override",
        metavar="REASON",
        help="proceed despite failures, recording REASON in .feanor/logs/overrides.log",
    )


def record_override(check_name: str, reason: str, failures: list[str]) -> None:
    OVERRIDE_LOG.parent.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).isoformat()
    with OVERRIDE_LOG.open("a", encoding="utf-8") as log:
        log.write(f"\n=== {stamp} — {check_name} ===\n")
        log.write(f"reason: {reason}\n")
        for failure in failures:
            log.write(f"  bypassed: {failure}\n")


def finish(
    check_name: str,
    failures: list[str],
    warnings: list[str] | None = None,
    override: str | None = None,
    ok_message: str | None = None,
) -> None:
    """Print results and exit. Never returns.

    Exit 0 when there are no failures, or when an override was given.
    Exit 1 otherwise. Warnings never affect the exit code — a check that blocks
    on something uncertain gets ignored, the same way a noisy alert does.
    """
    for warning in warnings or []:
        print(f"WARN  {warning}")

    if not failures:
        print(ok_message or f"OK — {check_name} passed.")
        sys.exit(0)

    for failure in failures:
        print(f"FAIL  {failure}")

    if override:
        record_override(check_name, override, failures)
        print(
            f"\nOVERRIDDEN ({len(failures)} failure(s)) — reason: {override}\n"
            f"Recorded in {OVERRIDE_LOG}."
        )
        sys.exit(0)

    print(
        f"\nBLOCKED — {check_name}: {len(failures)} failure(s).\n"
        f"Fix them, or re-run with --override \"<reason>\" if this check is wrong."
    )
    sys.exit(1)
