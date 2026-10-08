# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Phase precondition gate. Replaces the bash comment block in command-router section 2.

Every Feanor command has hard preconditions: artifacts that must exist on disk
before the phase can run. Those checks are mechanical, so they belong here rather
than in prose an agent re-derives each run.

Usage (from project root):
  uv run feanor/scripts/check-preconditions.py /prd
  uv run feanor/scripts/check-preconditions.py /exec
  uv run feanor/scripts/check-preconditions.py /plan --override "specs intentionally deferred"
  uv run feanor/scripts/check-preconditions.py --list

Exits 0 when the phase may run, 1 naming the missing artifact and the command
that produces it.
"""

import argparse
import json
import sys
from pathlib import Path

from _gate import add_override_arg, finish

SRS = Path("docs/SRS.md")
PRD = Path("docs/PRD.md")
ARCHITECTURE = Path("docs/ARCHITECTURE.md")
SPECS_DIR = Path("docs/specs")
PLAN = Path("docs/plan.toml")
STATUS = Path(".feanor/state/status.json")


def has_source() -> bool:
    if Path("backend").is_dir() or Path("frontend").is_dir():
        return True
    services = Path("services")
    return services.is_dir() and any(p.is_dir() for p in services.iterdir())


def _marker(name: str) -> bool:
    if not STATUS.exists():
        return False
    try:
        return json.loads(STATUS.read_text(encoding="utf-8")).get(name) is True
    except (json.JSONDecodeError, OSError):
        return False


def is_standardized() -> bool:
    """True only when /standardize wrote a clean-pass marker."""
    return _marker("standardized")


def is_scaffolded() -> bool:
    """True only when /scaffold created this source tree.

    Source existing is not the same question. A greenfield project has source
    the moment /scaffold runs, and requiring /standardize of it would be wrong —
    Feanor just built it to its own conventions. This marker separates the two.
    """
    return _marker("scaffolded")


def is_brownfield() -> bool:
    """Source that predates Feanor, so its compliance is unknown."""
    return has_source() and not is_scaffolded()


def specs_present() -> bool:
    return SPECS_DIR.is_dir() and any(SPECS_DIR.glob("*.md"))


def require(condition: bool, missing: str, produced_by: str) -> list[str]:
    return [] if condition else [f"missing {missing} — run {produced_by} first"]


def check(command: str) -> tuple[list[str], list[str]]:
    """Return (failures, warnings) for one command."""
    failures: list[str] = []
    warnings: list[str] = []

    match command:
        case "/reqs" | "/brainstorm" | "/document" | "/standardize":
            pass  # entry points — always allowed, by design

        case "/prd" | "/hld":
            failures += require(SRS.exists(), str(SRS), "/reqs")

        case "/scaffold":
            failures += require(ARCHITECTURE.exists(), str(ARCHITECTURE), "/hld")

        case "/specs":
            failures += require(ARCHITECTURE.exists(), str(ARCHITECTURE), "/hld")
            if is_brownfield() and not is_standardized():
                # ARCHITECTURE.md existing is not proof a brownfield project is
                # update-ready; the marker is. See command-router section 2.
                failures.append(
                    "brownfield project without a standardized:true marker — run /standardize first"
                )

        case "/plan":
            failures += require(ARCHITECTURE.exists(), str(ARCHITECTURE), "/hld")
            failures += require(specs_present(), f"{SPECS_DIR}/*.md", "/specs")
            # Tickets name target_files in the scaffolded tree, so planning before
            # /scaffold produces paths that do not exist yet. Nothing downstream
            # catches that — plan.py validates tag vocabulary and dependency
            # shape, not whether a target directory is real.
            failures += require(
                has_source(),
                "a scaffolded source directory (backend/, frontend/, or services/*)",
                "/scaffold",
            )
            if is_brownfield() and not is_standardized():
                failures.append(
                    "brownfield project without a standardized:true marker — run /standardize first"
                )

        case "/exec":
            failures += require(PLAN.exists(), str(PLAN), "/plan")

        case "/audit":
            failures += require(has_source(), "a source directory (backend/, frontend/, services/*)", "/scaffold")

        case _:
            failures.append(
                f"unknown command {command!r} — see meta/command-router.md section 1"
            )

    if command in {"/hld", "/plan"} and SRS.exists() and not PRD.exists():
        warnings.append(f"{PRD} does not exist — /prd is recommended before {command}")

    return failures, warnings


COMMANDS = [
    "/brainstorm", "/reqs", "/prd", "/hld", "/scaffold",
    "/specs", "/plan", "/exec", "/audit", "/document", "/standardize",
]


def normalise_command(raw: str) -> str:
    """Accept '/plan', 'plan', or a value MSYS has mangled into a Windows path.

    Git Bash on Windows rewrites a leading-slash argument into a filesystem path,
    so `check-preconditions.py /plan` arrives as 'C:/Program Files/Git/plan'.
    Taking the final segment recovers the command on every platform, and a real
    command never contains a separator.
    """
    candidate = raw.replace("\\", "/").rstrip("/")
    if "/" in candidate:
        candidate = candidate.rsplit("/", 1)[-1]
    return f"/{candidate.lstrip('/')}"


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("command", nargs="?", help="the phase command, e.g. /plan")
    parser.add_argument("--list", action="store_true", help="list every known command")
    add_override_arg(parser)
    args = parser.parse_args()

    if args.list:
        for name in COMMANDS:
            print(name)
        sys.exit(0)

    if not args.command:
        parser.error("give a command, e.g. /plan")

    command = normalise_command(args.command)
    failures, warnings = check(command)

    finish(
        check_name=f"preconditions {command}",
        failures=failures,
        warnings=warnings,
        override=args.override,
        ok_message=f"OK — preconditions for {command} are met.",
    )


if __name__ == "__main__":
    main()
