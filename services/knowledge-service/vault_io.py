"""Read and write markdown notes in the flat commons vault."""

import os
import re
import unicodedata

import frontmatter
import yaml

VAULT_ROOT = os.environ.get("VAULT_ROOT", os.path.expanduser("~/.nizam-vault"))
COMMONS_DIR = os.path.join(VAULT_ROOT, "commons")

DOMAINS = {
    "technology",
    "science",
    "business",
    "finance-economics",
    "philosophy-ethics",
    "health-wellness",
    "arts-culture",
    "history-society",
    "language-communication",
    "personal-development",
}


def slugify(text: str) -> str:
    """Convert arbitrary text to a lowercase, hyphenated filesystem slug."""
    text = unicodedata.normalize("NFKD", text)
    text = text.encode("ascii", "ignore").decode("ascii")
    text = re.sub(r"[^\w\s-]", "", text).strip().lower()
    return re.sub(r"[\s_]+", "-", text)


def note_path(title: str, domain: str, subdomain: str) -> str:
    """Return the canonical file path for a note under commons/."""
    filename = f"{slugify(domain)}--{slugify(subdomain)}--{slugify(title)}.md"
    return os.path.join(COMMONS_DIR, filename)


def read_note(file_path: str) -> tuple[dict, str]:
    """Parse a vault note. Returns (frontmatter_dict, body_text)."""
    post = frontmatter.load(file_path)
    return dict(post.metadata), post.content


def write_note(file_path: str, metadata: dict, body: str) -> None:
    """Write frontmatter + body to file_path, creating parent dirs as needed."""
    os.makedirs(os.path.dirname(file_path), exist_ok=True)
    post = frontmatter.Post(body, **metadata)
    with open(file_path, "w", encoding="utf-8") as fh:
        fh.write(frontmatter.dumps(post))
        fh.write("\n")


def render_draft(metadata: dict, body: str) -> str:
    """Return a human-readable draft preview string."""
    fm_block = yaml.dump(metadata, default_flow_style=False, allow_unicode=True).strip()
    preview = body[:500] + ("..." if len(body) > 500 else "")
    return f"---\n{fm_block}\n---\n\n{preview}"
