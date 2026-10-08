# /// script
# requires-python = ">=3.11"
# dependencies = ["pyyaml"]
# ///
"""Feanor OKF frontmatter validator.

Lints every Markdown file under feanor/ against the frontmatter schema in
workflows/maintain-repo.md section 2: type, title, description, applies_to, tags.

Usage (from the repo root):
  uv run feanor/scripts/validate-okf.py            # lint, exit 1 on any error
  uv run feanor/scripts/validate-okf.py --quiet    # only print failures

The frontmatter block is parsed with yaml.safe_load rather than line-by-line
regex. A hand-rolled parser silently mis-reads quoted values, colons inside
values, and multi-line scalars, which makes a lint gate that reports success on
input it never actually understood.
"""

import sys
import tomllib
from pathlib import Path

try:
    import yaml
except ModuleNotFoundError:
    from _gate import require_uv_run

    require_uv_run("pyyaml")

FEANOR_ROOT = Path(__file__).resolve().parent.parent

VALID_TYPES = {
    "catalog", "workflow", "convention", "template",
    "engine", "meta", "agent", "skill", "reference",
}
# `status` is deliberately NOT required. Every file in the corpus is live and
# normative, so a status on all of them carries no signal; a convention that no
# longer holds is deleted, not flagged, because an agent loading it JIT would
# follow it regardless. Validated only if a file chooses to set it.
VALID_STATUS = {"draft", "stable", "deprecated"}
REQUIRED_LIST_FIELDS = ("applies_to", "tags")
REQUIRED_STR_FIELDS = ("type", "title", "description")

# Files that carry no OKF frontmatter by design.
SKIP_FILES = {"README.md"}
# Generated artifacts and local state — not part of the authored corpus.
SKIP_DIRS = {"graphify-out"}

MIN_DESCRIPTION_LEN = 40


def split_frontmatter(content: str) -> str | None:
    """Return the raw YAML block between the leading '---' fences, or None."""
    if not content.startswith("---"):
        return None
    lines = content.splitlines()
    if lines[0].strip() != "---":
        return None
    for i, line in enumerate(lines[1:], start=1):
        if line.strip() == "---":
            return "\n".join(lines[1:i])
    return None


def validate_file(file_path: Path) -> list[str]:
    try:
        content = file_path.read_text(encoding="utf-8")
    except OSError as exc:
        return [f"could not read file: {exc}"]

    raw = split_frontmatter(content)
    if raw is None:
        return ["missing YAML frontmatter block (--- ... ---) at the start of the file"]

    try:
        data = yaml.safe_load(raw)
    except yaml.YAMLError as exc:
        return [f"frontmatter is not valid YAML: {str(exc).splitlines()[0]}"]

    if not isinstance(data, dict):
        return ["frontmatter must be a YAML mapping of fields"]

    errors: list[str] = []

    for field in REQUIRED_STR_FIELDS:
        value = data.get(field)
        if value is None or (isinstance(value, str) and not value.strip()):
            errors.append(f"missing mandatory frontmatter field: '{field}'")
        elif not isinstance(value, str):
            errors.append(f"'{field}' must be a string, got {type(value).__name__}")

    for field in REQUIRED_LIST_FIELDS:
        value = data.get(field)
        if value is None:
            errors.append(f"missing mandatory frontmatter field: '{field}'")
        elif not isinstance(value, list) or not value:
            errors.append(f"'{field}' must be a non-empty list")

    file_type = data.get("type")
    if isinstance(file_type, str) and file_type not in VALID_TYPES:
        errors.append(f"invalid type '{file_type}' — must be one of: {', '.join(sorted(VALID_TYPES))}")

    status = data.get("status")
    if isinstance(status, str) and status not in VALID_STATUS:
        errors.append(f"invalid status '{status}' — must be one of: {', '.join(sorted(VALID_STATUS))}")

    # The description is what the Context Resolver reads when deciding whether to
    # load a file, so a one-word description defeats JIT retrieval.
    # See meta/determinism-standard.md, "Frontmatter description field mandate".
    description = data.get("description")
    if isinstance(description, str) and 0 < len(description.strip()) < MIN_DESCRIPTION_LEN:
        errors.append(
            f"description is {len(description.strip())} chars — too short to answer "
            f"'is this the right file to load?' (minimum {MIN_DESCRIPTION_LEN})"
        )

    return errors


def iter_markdown(root: Path):
    for path in sorted(root.rglob("*.md")):
        rel = path.relative_to(root)
        if any(part.startswith(".") for part in rel.parts):
            continue
        if any(part in SKIP_DIRS for part in rel.parts):
            continue
        if path.name in SKIP_FILES:
            continue
        yield path, rel


def validate_tag_map() -> list[str]:
    """Every path in conventions/tags.toml must exist, and aliases must not collide.

    A tag pointing at a missing file fails silently at execution time — the agent
    just works without those rules — so it has to be caught here.
    """
    tags_path = FEANOR_ROOT / "conventions" / "tags.toml"
    if not tags_path.exists():
        return ["conventions/tags.toml is missing — the Context Resolver has no mapping"]

    try:
        with tags_path.open("rb") as f:
            tags = tomllib.load(f).get("tags", {})
    except tomllib.TOMLDecodeError as exc:
        return [f"conventions/tags.toml is not valid TOML: {exc}"]

    errors: list[str] = []
    seen_aliases: dict[str, str] = {}

    for name, entry in tags.items():
        for rel in entry.get("files", []):
            if not (FEANOR_ROOT / rel).exists():
                errors.append(f"tags.toml: tag '{name}' points at missing file '{rel}'")
        if not entry.get("files"):
            errors.append(f"tags.toml: tag '{name}' has no files")
        for alias in entry.get("aliases", []):
            if alias in tags:
                errors.append(f"tags.toml: alias '{alias}' collides with canonical tag '{alias}'")
            if alias in seen_aliases and seen_aliases[alias] != name:
                errors.append(
                    f"tags.toml: alias '{alias}' claimed by '{seen_aliases[alias]}' and '{name}'"
                )
            seen_aliases[alias] = name

    return errors


def main() -> None:
    quiet = "--quiet" in sys.argv[1:]
    print(f"Validating OKF metadata compliance in: {FEANOR_ROOT}\n")

    total = 0
    failed_files = 0

    for path, rel in iter_markdown(FEANOR_ROOT):
        total += 1
        errors = validate_file(path)
        if errors:
            failed_files += 1
            print(f"FAIL  {rel}")
            for err in errors:
                print(f"        {err}")
        elif not quiet:
            print(f"ok    {rel}")

    tag_errors = validate_tag_map()
    for err in tag_errors:
        print(f"FAIL  {err}")

    print(
        f"\nChecked {total} files, {failed_files} with errors. "
        f"Tag map: {len(tag_errors)} error(s)."
    )
    if failed_files or tag_errors:
        print("Result: FAILED.")
        sys.exit(1)
    print("Result: PASSED.")
    sys.exit(0)


if __name__ == "__main__":
    main()
