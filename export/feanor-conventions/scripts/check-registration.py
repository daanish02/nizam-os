# /// script
# requires-python = ">=3.12"
# dependencies = ["pyyaml"]
# ///
"""Cross-check Feanor's own internal references. Catches drift between files.

Adding a file is never enough: Feanor finds things through catalogs, a manifest,
a tag map, and agent prompts. An unregistered file exists on disk and is
invisible to every agent — and nothing errors, which is what makes this class of
bug survive. Every consistency defect found in the 2026-09-07 audit was this
shape: a reference to something that did not exist, or a thing that existed and
was referenced nowhere.

Checks:
  - .feanor-manifest.yaml commands <-> command-router.md <-> agents/ files
  - every agents/ and workflows/ file appears in its index.md
  - every scripts/ entry appears in scripts/index.md
  - every templates/ file is referenced by some agent or template index
  - every relative markdown link resolves
  - convention files reachable by neither a tag nor a path rule (warning)

Usage (from project root):
  uv run feanor/scripts/check-registration.py
  uv run feanor/scripts/check-registration.py --override "reason"
"""

import argparse
import re
import sys
import tomllib
from pathlib import Path

try:
    import yaml
except ModuleNotFoundError:
    from _gate import require_uv_run

    require_uv_run("pyyaml")

from _gate import add_override_arg, finish

FEANOR_ROOT = Path(__file__).resolve().parent.parent
LINK = re.compile(r"\[[^\]]*\]\(([^)#]+?)(?:#[^)]*)?\)")
SKIP_DIRS = {"graphify-out", "__pycache__"}


def markdown_files() -> list[Path]:
    return [
        p for p in sorted(FEANOR_ROOT.rglob("*.md"))
        if not any(part in SKIP_DIRS or part.startswith(".") for part in p.relative_to(FEANOR_ROOT).parts)
    ]


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except OSError:
        return ""


def check_links() -> list[str]:
    """Every relative markdown link must resolve. This is the check that would
    have caught agents/intake-agent.md being referenced from two files."""
    failures = []
    for md in markdown_files():
        for target in LINK.findall(read(md)):
            target = target.strip()
            if target.startswith(("http://", "https://", "mailto:", "{{")):
                continue
            if not (md.parent / target).resolve().exists():
                rel = md.relative_to(FEANOR_ROOT).as_posix()
                failures.append(f"broken link: {rel} -> {target}")
    return failures


def check_commands() -> list[str]:
    """The manifest, the router, and agents/ must agree on what exists."""
    failures = []
    manifest_path = FEANOR_ROOT / ".feanor-manifest.yaml"
    router_path = FEANOR_ROOT / "meta" / "command-router.md"

    if not manifest_path.exists():
        return ["missing .feanor-manifest.yaml"]

    try:
        manifest = yaml.safe_load(read(manifest_path)) or {}
    except yaml.YAMLError as exc:
        return [f".feanor-manifest.yaml is not valid YAML: {exc}"]

    router_text = read(router_path)
    manifest_commands = {}

    for entry in manifest.get("supported_commands", []):
        command = entry.get("command", "")
        engine = entry.get("engine", "")
        manifest_commands[command] = engine

        if engine:
            engine_path = (FEANOR_ROOT / engine.lstrip("./")).resolve()
            if not engine_path.exists():
                failures.append(
                    f"manifest: {command} -> engine '{engine}' does not exist"
                )
        if command and f"`{command}`" not in router_text:
            failures.append(
                f"manifest: {command} is not documented in meta/command-router.md"
            )

    # Every agent file the router names must exist.
    for referenced in set(re.findall(r"agents/([a-z0-9-]+\.md)", router_text)):
        if not (FEANOR_ROOT / "agents" / referenced).exists():
            failures.append(f"command-router.md references missing agents/{referenced}")

    return failures


def check_catalog(directory: str, pattern: str = "*.md") -> list[str]:
    """Every file in a directory must be linked from that directory's index.md."""
    failures = []
    dir_path = FEANOR_ROOT / directory
    index_path = dir_path / "index.md"
    if not index_path.exists():
        return [f"{directory}/index.md is missing"]

    index_text = read(index_path)
    for item in sorted(dir_path.glob(pattern)):
        if item.name == "index.md" or item.name.startswith("_"):
            continue
        if item.name not in index_text:
            failures.append(f"{directory}/{item.name} is not listed in {directory}/index.md")
    return failures


def check_scripts() -> list[str]:
    failures = []
    index_text = read(FEANOR_ROOT / "scripts" / "index.md")
    for item in sorted((FEANOR_ROOT / "scripts").iterdir()):
        if item.is_dir() or item.name in {"index.md"} or item.name.startswith("_"):
            continue
        if item.name not in index_text:
            failures.append(f"scripts/{item.name} is not listed in scripts/index.md")
    return failures


def check_templates() -> list[str]:
    """A template no agent reads is never used."""
    failures = []
    corpus = "\n".join(read(p) for p in markdown_files())
    for template in sorted((FEANOR_ROOT / "templates").rglob("*.md")):
        if template.name == "index.md":
            continue
        if template.name not in corpus:
            rel = template.relative_to(FEANOR_ROOT).as_posix()
            failures.append(f"{rel} is referenced by nothing — no agent will ever read it")
    return failures


def check_convention_reachability() -> list[str]:
    """Warning-level: conventions reachable by neither a tag nor a path rule."""
    tags_path = FEANOR_ROOT / "conventions" / "tags.toml"
    if not tags_path.exists():
        return ["conventions/tags.toml is missing"]
    with tags_path.open("rb") as f:
        tags = tomllib.load(f).get("tags", {})

    mapped = {rel for entry in tags.values() for rel in entry.get("files", [])}
    warnings = []
    for path in sorted((FEANOR_ROOT / "conventions").rglob("*.md")):
        rel = path.relative_to(FEANOR_ROOT).as_posix()
        if path.name == "index.md" or rel in mapped:
            continue
        warnings.append(f"{rel} has no tag — reachable only by path-match")
    return warnings


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    add_override_arg(parser)
    args = parser.parse_args()

    failures: list[str] = []
    failures += check_links()
    failures += check_commands()
    failures += check_catalog("agents")
    failures += check_catalog("workflows")
    failures += check_catalog("meta")
    failures += check_scripts()
    failures += check_templates()

    warnings = check_convention_reachability()

    finish(
        check_name="registration",
        failures=failures,
        warnings=warnings,
        override=args.override,
        ok_message="OK — registration consistent: links resolve, commands agree, catalogs complete.",
    )


if __name__ == "__main__":
    main()
