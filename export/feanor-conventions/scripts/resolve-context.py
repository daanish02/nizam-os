# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""Resolve a ticket's convention tags and target files into the exact file list to load.

This is the deterministic half of meta/context-resolver.md. Tag lookup, the
priority ladder, the always-load floor, the profile gate, and the payload cap all
have exactly one correct outcome, so per meta/determinism-standard.md they belong
in a tested script rather than in prose an agent re-derives each run. Choosing the
tags in the first place stays judgment, and stays with the Planner.

Usage (from project root):
  uv run feanor/scripts/resolve-context.py --tags coding-principles,tdd,auth \\
      --files backend/app/auth/router.py

  uv run feanor/scripts/resolve-context.py --tags python --files backend/app/x.py --explain
  uv run feanor/scripts/resolve-context.py --list-tags
  uv run feanor/scripts/resolve-context.py --validate

Prints one file path per line, already ordered, deduplicated, and capped.
"""

import argparse
import sys
import tomllib
from pathlib import Path

FEANOR_ROOT = Path(__file__).resolve().parent.parent
TAGS_PATH = FEANOR_ROOT / "conventions" / "tags.toml"
PROFILE_PATH = Path(".feanor/profile.toml")

MAX_FILES = 10
LANGUAGE_PREFIXES = ("go-", "python-", "nextjs-", "typescript-", "ts-")

# Path fragments that mean "this ticket touches a request entry point", which is
# where missing authorization actually happens. A passing test suite looks
# identical with and without the ownership check, so this cannot be left to the
# planner remembering the tag.
HANDLER_MARKERS = (
    "router", "handler", "controller", "routes", "route",
    "actions", "resolver", "endpoint", "views", "/api/",
)

# Loaded for every ticket regardless of tags — see the commit floor below.
COMMIT_FORMAT = "conventions/git/commit-format.md"


def load_tags() -> dict:
    with TAGS_PATH.open("rb") as f:
        return tomllib.load(f)["tags"]


def load_profile() -> dict | None:
    if not PROFILE_PATH.exists():
        return None
    with PROFILE_PATH.open("rb") as f:
        return tomllib.load(f)


def build_alias_index(tags: dict) -> dict[str, str]:
    """Map every accepted spelling of a tag to its canonical name."""
    index: dict[str, str] = {}
    for canonical, entry in tags.items():
        index[canonical] = canonical
        for alias in entry.get("aliases", []):
            index[alias] = canonical
    return index


def canonicalise(tag: str, alias_index: dict[str, str]) -> str | None:
    tag = tag.strip().lower()
    if not tag:
        return None
    if tag in alias_index:
        return alias_index[tag]
    # Language-qualified form: go-auth -> auth, when that entry allows it.
    for prefix in LANGUAGE_PREFIXES:
        if tag.startswith(prefix):
            base = tag[len(prefix):]
            canonical = alias_index.get(base)
            return canonical
    return None


def capability_enabled(entry: dict, profile: dict | None) -> bool:
    """An optional capability's conventions load only when the project enabled it."""
    capability = entry.get("requires_capability")
    if capability is None:
        return True
    if profile is None:
        # No profile (brownfield, or predates profiles) means no gating.
        return True
    return bool(profile.get("optional", {}).get(capability, False))


def resolve(
    tag_list: list[str],
    file_list: list[str],
    tags: dict,
    profile: dict | None,
) -> tuple[list[tuple[str, int, str]], list[str]]:
    """Return (selected, warnings). Each selected item is (path, priority, reason)."""
    alias_index = build_alias_index(tags)
    selected: dict[str, tuple[int, str]] = {}
    warnings: list[str] = []

    def add(path: str, priority: int, reason: str) -> None:
        existing = selected.get(path)
        if existing is None or priority < existing[0]:
            selected[path] = (priority, reason)

    for raw in tag_list:
        canonical = canonicalise(raw, alias_index)
        if canonical is None:
            warnings.append(f"unknown tag {raw!r} — not in conventions/tags.toml")
            continue
        entry = tags[canonical]
        if not capability_enabled(entry, profile):
            warnings.append(
                f"tag {raw!r} skipped: capability "
                f"{entry['requires_capability']!r} is disabled in {PROFILE_PATH}"
            )
            continue
        for path in entry["files"]:
            add(path, entry.get("priority", 4), f"tag:{canonical}")

    # Extension fallback for underspecified tickets.
    joined = " ".join(file_list).lower()
    if any(f.endswith(".py") for f in file_list):
        for path in tags["python"]["files"]:
            add(path, 3, "path:.py")
    if any(f.endswith(".go") for f in file_list):
        for path in tags["go"]["files"]:
            add(path, 3, "path:.go")
    if any(f.endswith((".ts", ".tsx")) for f in file_list):
        for path in tags["typescript"]["files"]:
            add(path, 3, "path:.ts")
        if "frontend/" in joined:
            for path in tags["nextjs"]["files"]:
                add(path, 3, "path:frontend")
    if any("dockerfile" in f.lower() for f in file_list):
        for path in tags["docker"]["files"]:
            add(path, 5, "path:Dockerfile")

    # Security floor — applies regardless of tags and regardless of the cap.
    if any(marker in joined for marker in HANDLER_MARKERS):
        for path in tags["access-control"]["files"]:
            add(path, 0, "floor:request entry point")

    # Commit floor — every ticket ends in a commit, so the rules for shaping one
    # apply to every ticket. Reaching them by tag never happened: `git` sits at
    # priority 5 and application tickets are not tagged `git`, so in a full live
    # run the commit conventions were never once loaded and the history came out
    # as 74-file commits. A rule that applies always must load always.
    add(COMMIT_FORMAT, 0, "floor:every ticket ends in a commit")

    ordered = sorted(
        ((path, pri, reason) for path, (pri, reason) in selected.items()),
        key=lambda item: (item[1], item[0]),
    )

    if len(ordered) > MAX_FILES:
        dropped = ordered[MAX_FILES:]
        warnings.append(
            f"{len(ordered)} files matched, capped at {MAX_FILES}. "
            f"Dropped: {', '.join(p for p, _, _ in dropped)}. "
            f"A ticket needing this many conventions is doing more than one thing — split it."
        )
        ordered = ordered[:MAX_FILES]

    return ordered, warnings


def cmd_validate(tags: dict) -> int:
    """Every mapped path exists; every convention file is reachable by some tag."""
    problems = []
    mapped: set[str] = set()

    for name, entry in tags.items():
        if "files" not in entry:
            problems.append(f"tag '{name}' has no files list")
            continue
        for rel in entry["files"]:
            mapped.add(rel)
            if not (FEANOR_ROOT / rel).exists():
                problems.append(f"tag '{name}' -> missing file: {rel}")

    seen_aliases: dict[str, str] = {}
    for name, entry in tags.items():
        for alias in entry.get("aliases", []):
            if alias in seen_aliases:
                problems.append(
                    f"alias '{alias}' claimed by both '{seen_aliases[alias]}' and '{name}'"
                )
            seen_aliases[alias] = name
            if alias in tags:
                problems.append(f"alias '{alias}' collides with canonical tag '{alias}'")

    unreachable = [
        p.relative_to(FEANOR_ROOT).as_posix()
        for p in (FEANOR_ROOT / "conventions").rglob("*.md")
        if p.name != "index.md" and p.relative_to(FEANOR_ROOT).as_posix() not in mapped
    ]

    for problem in problems:
        print(f"FAIL  {problem}")
    if unreachable:
        print(f"\nWARN  {len(unreachable)} convention file(s) reachable by path-match only:")
        for path in sorted(unreachable):
            print(f"        {path}")

    if problems:
        print(f"\n{len(problems)} error(s).")
        return 1
    print(f"\nOK — {len(tags)} tags, {len(mapped)} mapped files, all present.")
    return 0


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("--tags", default="", help="comma-separated convention tags")
    parser.add_argument("--files", default="", help="comma-separated target file paths")
    parser.add_argument("--explain", action="store_true", help="show why each file was selected")
    parser.add_argument("--list-tags", action="store_true", help="list every known tag")
    parser.add_argument("--validate", action="store_true", help="check the mapping's integrity")
    args = parser.parse_args()

    tags = load_tags()

    if args.validate:
        sys.exit(cmd_validate(tags))

    if args.list_tags:
        for name in sorted(tags):
            entry = tags[name]
            aliases = ", ".join(entry.get("aliases", []))
            gate = entry.get("requires_capability")
            suffix = f"  [needs capability: {gate}]" if gate else ""
            print(f"{name:22} p{entry.get('priority', 4)}  {aliases}{suffix}")
        return

    tag_list = [t for t in args.tags.split(",") if t.strip()]
    file_list = [f for f in args.files.split(",") if f.strip()]
    if not tag_list and not file_list:
        parser.error("give --tags and/or --files")

    selected, warnings = resolve(tag_list, file_list, tags, load_profile())

    for warning in warnings:
        print(f"# WARNING: {warning}", file=sys.stderr)

    for path, priority, reason in selected:
        print(f"{path}    # p{priority} {reason}" if args.explain else path)


if __name__ == "__main__":
    main()
