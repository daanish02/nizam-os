#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# dependencies = ["PyYAML"]
# ///
"""
Validate a SKILL.md file against nizam-os SAVE framework requirements.

Exit 0 = valid. Exit 1 = validation errors printed to stderr.

Usage:
  python3 scripts/save/validate-skill.py path/to/SKILL.md
  python3 scripts/save/validate-skill.py hermes/profiles/admin/skills/system-administration/server-healthcheck/SKILL.md
"""

import re
import sys
from pathlib import Path

import yaml

MAX_FILE_CHARS = 100_000
MAX_NAME_LEN = 64
MAX_DESC_LEN = 200
VALID_NAME_RE = re.compile(r'^[a-z0-9][a-z0-9-]*$')


def parse_frontmatter(text: str) -> tuple[dict, str]:
    """Return (frontmatter_dict, body). Raises ValueError if no frontmatter."""
    if not text.startswith("---"):
        raise ValueError("no YAML frontmatter block (must start with ---)")
    end = text.find("\n---", 3)
    if end == -1:
        raise ValueError("frontmatter block not closed (missing closing ---)")
    raw_yaml = text[3:end].strip()
    body = text[end + 4:].lstrip()
    try:
        fm = yaml.safe_load(raw_yaml) or {}
    except yaml.YAMLError as e:
        raise ValueError(f"frontmatter YAML parse error: {e}") from e
    if not isinstance(fm, dict):
        raise ValueError("frontmatter must be a YAML mapping")
    return fm, body


def validate(path: Path) -> list[str]:
    errors: list[str] = []

    if not path.exists():
        return [f"file not found: {path}"]
    if not path.name == "SKILL.md":
        errors.append("file must be named SKILL.md")

    text = path.read_text(encoding="utf-8", errors="replace")

    if len(text) > MAX_FILE_CHARS:
        errors.append(f"file too large: {len(text):,} chars (max {MAX_FILE_CHARS:,})")

    try:
        fm, _body = parse_frontmatter(text)
    except ValueError as e:
        errors.append(str(e))
        return errors  # can't check fields without frontmatter

    # Required fields
    for field in ("name", "description", "version", "author"):
        val = fm.get(field)
        if not val or not str(val).strip():
            errors.append(f"missing required frontmatter field: {field}")

    # name format
    name = str(fm.get("name") or "")
    if name:
        if len(name) > MAX_NAME_LEN:
            errors.append(f"name too long: {len(name)} chars (max {MAX_NAME_LEN})")
        if not VALID_NAME_RE.match(name):
            errors.append(f"name must be lowercase letters, digits, hyphens only: got '{name}'")

    # description length
    desc = str(fm.get("description") or "")
    if desc and len(desc) > MAX_DESC_LEN:
        errors.append(f"description too long: {len(desc)} chars (max {MAX_DESC_LEN})")

    # tags
    hermes_meta = (fm.get("metadata") or {}).get("hermes") or {}
    tags = hermes_meta.get("tags")
    if not tags:
        errors.append("missing metadata.hermes.tags (must be a non-empty list)")
    elif not isinstance(tags, list) or len(tags) == 0:
        errors.append("metadata.hermes.tags must be a non-empty list")

    # version format (semver-ish)
    version = str(fm.get("version") or "")
    if version and not re.match(r'^\d+\.\d+\.\d+', version):
        errors.append(f"version should be semver (e.g. 1.0.0): got '{version}'")

    return errors


def main() -> None:
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} path/to/SKILL.md", file=sys.stderr)
        sys.exit(2)

    path = Path(sys.argv[1])
    errors = validate(path)

    if errors:
        print(f"INVALID: {path}", file=sys.stderr)
        for e in errors:
            print(f"  ✗ {e}", file=sys.stderr)
        sys.exit(1)
    else:
        print(f"✓ valid: {path}")


if __name__ == "__main__":
    main()
