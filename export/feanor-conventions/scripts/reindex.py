#!/usr/bin/env python3
"""
Feanor OKF Catalog Reindexer (reindex.py)

Scans the lattice/feanor/ tree, parses Markdown file frontmatter, and 
auto-generates compliant index.md catalogs for every subdirectory.
"""

import os
import re
import sys
from pathlib import Path

FEANOR_ROOT = Path(__file__).resolve().parent.parent

FRONTMATTER_PATTERN = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)

def extract_title_and_desc(file_path: Path):
    """Extracts title and description from YAML frontmatter or falls back to filename."""
    try:
        content = file_path.read_text(encoding="utf-8")
        match = FRONTMATTER_PATTERN.match(content)
        if match:
            raw_yaml = match.group(1)
            title_match = re.search(r"^title:\s*(.+)$", raw_yaml, re.MULTILINE)
            desc_match = re.search(r"^description:\s*(.+)$", raw_yaml, re.MULTILINE)
            
            title = title_match.group(1).strip("'\"") if title_match else None
            desc = desc_match.group(1).strip("'\"") if desc_match else None
            return title, desc
    except OSError as exc:
        # Never swallow this silently: a file that can't be read drops out of the
        # index the Context Resolver navigates by, so the convention stops being
        # findable with no visible failure anywhere.
        print(f"WARNING: could not read {file_path}: {exc}", file=sys.stderr)


    clean_stem = file_path.stem.replace("-", " ").replace("_", " ").title()
    return clean_stem, f"Documentation for {clean_stem}."

def generate_catalog_for_dir(dir_path: Path):
    rel_path = dir_path.relative_to(FEANOR_ROOT)

    index_path = dir_path / "index.md"
    if index_path.exists():
        # Never overwrite a hand-curated catalog — this script only fills in
        # index.md files that don't exist yet. Existing catalogs (all of
        # Feanor's real index.md files) carry curated prose plus generated/
        # verified metadata this auto-generator doesn't produce; overwriting
        # them would silently destroy that.
        return

    # Exclude hidden directories and root feanor index if handled separately
    subdirs = sorted([d for d in dir_path.iterdir() if d.is_dir() and not d.name.startswith(".")])
    md_files = sorted([f for f in dir_path.glob("*.md") if f.name != "index.md"])

    if not subdirs and not md_files and rel_path != Path("."):
        return

    import datetime

    section_name = rel_path.as_posix() if rel_path != Path(".") else "Feanor Root"
    today = datetime.date.today().isoformat()

    lines = [
        "---",
        "type: catalog",
        f"title: Feanor Index - {section_name}",
        f"description: Automatically generated catalog index for {section_name}.",
        f"domain: feanor.{rel_path.as_posix().replace('/', '.')}" if rel_path != Path(".") else "domain: feanor.root",
        "tags: [auto-generated]",
        "status: draft",
        "generated:",
        "  by: agent",
        f"  at: {today}",
        "---\n",
        f"# Catalog: {section_name}\n"
    ]

    if subdirs:
        lines.append("## Subdirectories")
        for sd in subdirs:
            sd_index = sd / "index.md"
            title, _ = extract_title_and_desc(sd_index) if sd_index.exists() else (sd.name, "")
            lines.append(f"* [{sd.name}/](./{sd.name}/index.md) - {title}")
        lines.append("")

    if md_files:
        lines.append("## Document Nodes")
        for mf in md_files:
            title, desc = extract_title_and_desc(mf)
            lines.append(f"* [{title}](./{mf.name}) - {desc}")
        lines.append("")

    index_path = dir_path / "index.md"
    index_path.write_text("\n".join(lines), encoding="utf-8")

def main():
    print(f"Reindexing OKF catalogs in: {FEANOR_ROOT}")
    count = 0
    for root, dirs, _ in os.walk(FEANOR_ROOT):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        generate_catalog_for_dir(Path(root))
        count += 1
    print(f"Successfully reindexed {count} directories.")

if __name__ == "__main__":
    main()