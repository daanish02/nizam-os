#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# dependencies = ["requests"]
# ///
"""
Watches ~/.hermes/profiles/*/pending/skills/ via inotify and fires a Discord embed
when a new skill lands in the approval queue. Logs proposed/approved/rejected to
each profile's skills/.audit.json.

Requires:
  DISCORD_ADMIN_WEBHOOK — set in secrets/nizam.env (loaded by systemd EnvironmentFile)

State files (survive restarts):
  ~/.hermes/pending/.skill_notified     — set of already-notified pending keys
  ~/.hermes/pending/.skill_pending_map  — map of pending_filename → {profile, skill_name}
                                          used to detect rejection when pending JSON deleted

Pending file format (Hermes write_approval.py):
  {
    "id": "8d3a622c",
    "subsystem": "skills",
    "action": "create",
    "summary": "create 'test-skill-a' — ...",
    "origin": "assistant_tool",
    "created_at": 1782553910.996,
    "payload": { "action": "create", "name": "test-skill-a", "content": "---...", "category": "..." }
  }
"""

import json
import logging
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

import requests

logging.basicConfig(
    stream=sys.stdout,
    level=logging.INFO,
    format="%(asctime)s [%(levelname)-5s] [skill-watcher] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%SZ",
)
log = logging.getLogger("skill-watcher")

HERMES_PROFILES = Path.home() / ".hermes" / "profiles"
NIZAM_PROFILES = Path("/home/vazir/.nizam-os/hermes/profiles")
STATE_DIR = Path.home() / ".hermes" / "pending"
NOTIFIED_FILE = STATE_DIR / ".skill_notified"
PENDING_MAP_FILE = STATE_DIR / ".skill_pending_map"
WEBHOOK_URL = os.environ.get("DISCORD_ADMIN_WEBHOOK", "")

ACTION_COLOURS = {
    "create": 0xF5A623,
    "edit":   0x4A90D9,
    "patch":  0x7B68EE,
    "delete": 0xE74C3C,
}


# ── State persistence ─────────────────────────────────────────────────────────

def load_notified() -> set[str]:
    if NOTIFIED_FILE.exists():
        try:
            return set(json.loads(NOTIFIED_FILE.read_text()))
        except Exception:
            pass
    return set()


def save_notified(ids: set[str]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    NOTIFIED_FILE.write_text(json.dumps(sorted(ids)))


def load_pending_map() -> dict[str, dict]:
    """filename → {profile, skill_name, action}"""
    if PENDING_MAP_FILE.exists():
        try:
            return json.loads(PENDING_MAP_FILE.read_text())
        except Exception:
            pass
    return {}


def save_pending_map(m: dict[str, dict]) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    PENDING_MAP_FILE.write_text(json.dumps(m, indent=2))


# ── Parsing helpers ───────────────────────────────────────────────────────────

def parse_frontmatter(content: str) -> dict:
    if not content.startswith("---"):
        return {}
    end = content.find("\n---", 3)
    if end == -1:
        return {}
    block = content[3:end].strip()
    result: dict = {}
    for line in block.splitlines():
        m = re.match(r'^(\w[\w_-]*):\s*(.+)$', line.strip())
        if m:
            key, val = m.group(1), m.group(2).strip().strip('"')
            result[key] = val
    return result


def skill_body_excerpt(content: str, max_chars: int = 800) -> str:
    if content.startswith("---"):
        end = content.find("\n---", 3)
        if end != -1:
            content = content[end + 4:].lstrip()
    content = content.strip()
    if len(content) <= max_chars:
        return content
    return content[:max_chars].rsplit("\n", 1)[0] + "\n…"


# ── Discord ───────────────────────────────────────────────────────────────────

def send_discord(record: dict) -> None:
    if not WEBHOOK_URL:
        log.warning("DISCORD_ADMIN_WEBHOOK not set — cannot notify")
        return

    pending_id = record.get("id") or ""
    action = str(record.get("action") or "create").lower()
    summary = record.get("summary") or ""
    p = record.get("payload") or {}
    skill_name = p.get("name") or "unknown"
    content = p.get("content") or ""
    category = p.get("category") or ""

    fm = parse_frontmatter(content) if content else {}
    description = fm.get("description") or summary or ""
    version = fm.get("version") or "—"
    author = fm.get("author") or record.get("origin") or "agent"
    tags_raw = fm.get("tags") or ""
    tags_str = tags_raw.strip("[]").replace('"', '').replace("'", "") if tags_raw else ""
    body_excerpt = skill_body_excerpt(content) if content else ""

    embed: dict = {
        "title": f"🔏 Skill Approval Needed: `{skill_name}`",
        "color": ACTION_COLOURS.get(action, 0x95A5A6),
        "fields": [
            {"name": "Author", "value": author, "inline": True},
            {"name": "Action", "value": action, "inline": True},
            {"name": "Version", "value": version, "inline": True},
        ],
        "footer": {"text": "/skills pending  ·  /skills approve <id>  ·  /skills reject <id>"},
    }
    if description:
        embed["fields"].append({"name": "Description", "value": description, "inline": False})
    if category:
        embed["fields"].append({"name": "Category", "value": category, "inline": True})
    if tags_str:
        embed["fields"].append({"name": "Tags", "value": tags_str, "inline": True})
    if body_excerpt:
        embed["description"] = f"```markdown\n{body_excerpt}\n```"
    if pending_id:
        embed["fields"].append({"name": "Pending ID", "value": f"`{pending_id}`", "inline": False})

    try:
        r = requests.post(WEBHOOK_URL, json={"embeds": [embed]}, timeout=10)
        r.raise_for_status()
        log.info("notified Discord: %s %s (id=%s)", action, skill_name, pending_id)
    except Exception as e:
        log.error("Discord POST failed: %s", e)


# ── Audit log ─────────────────────────────────────────────────────────────────

def write_audit(profile: str, event: str, skill: str, actor: str, note: str = "") -> None:
    path = NIZAM_PROFILES / profile / "skills" / ".audit.json"
    try:
        entries = json.loads(path.read_text()) if path.exists() else []
    except Exception:
        entries = []
    entries.append({
        "event": event,
        "skill": skill,
        "actor": actor,
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "note": note,
    })
    path.write_text(json.dumps(entries, indent=2) + "\n")
    log.info("audit: %s %s (%s)", event, skill, profile)


# ── Event handlers ────────────────────────────────────────────────────────────

def on_pending_created(path: Path, notified: set[str], pending_map: dict) -> bool:
    """New pending JSON file. Notify Discord, log proposed, track in pending_map."""
    profile = path.parts[-4]
    key = f"{profile}:{path.name}"
    if key in notified:
        return False
    try:
        data = json.loads(path.read_text())
    except Exception as e:
        log.warning("could not parse %s: %s", path, e)
        return False
    if data.get("subsystem") != "skills":
        return False

    skill_name = (data.get("payload") or {}).get("name") or "unknown"
    action = data.get("action") or "create"
    pending_id = data.get("id") or path.stem

    send_discord(data)
    write_audit(profile, "proposed", skill_name, profile,
                note=f"action={action} pending_id={pending_id}")

    notified.add(key)
    pending_map[path.name] = {"profile": profile, "skill_name": skill_name, "action": action}
    return True


def on_pending_deleted(filename: str, pending_map: dict) -> None:
    """Pending JSON deleted. If still in map (no SKILL.md appeared) → rejected."""
    entry = pending_map.pop(filename, None)
    if not entry:
        return
    profile = entry["profile"]
    skill_name = entry["skill_name"]
    write_audit(profile, "rejected", skill_name, "user",
                note=f"pending file removed without SKILL.md appearing")
    log.info("audit: rejected %s (%s)", skill_name, profile)


def on_skill_created(path: Path, pending_map: dict) -> None:
    """New SKILL.md in skills dir. If matches a pending skill → approved, remove from map."""
    parts = path.parts
    try:
        profiles_idx = parts.index("profiles")
        profile = parts[profiles_idx + 1]
        skill_name = parts[-2]
    except (ValueError, IndexError):
        return

    # Find and remove from pending_map by skill_name + profile
    matched_file = None
    for fname, entry in pending_map.items():
        if entry["profile"] == profile and entry["skill_name"] == skill_name:
            matched_file = fname
            break

    if matched_file:
        pending_map.pop(matched_file, None)
        write_audit(profile, "approved", skill_name, "user",
                    note="SKILL.md appeared in skills dir after pending gate")
    else:
        # SKILL.md appeared but wasn't in pending map (pre-SAVE or manual) — still log
        write_audit(profile, "approved", skill_name, "user",
                    note="SKILL.md appeared (not tracked in pending map — pre-SAVE or manual)")


# ── Startup scan ──────────────────────────────────────────────────────────────

def scan_existing(notified: set[str], pending_map: dict) -> None:
    """On startup: notify for any pending files not yet announced."""
    if not HERMES_PROFILES.exists():
        return
    for profile_dir in HERMES_PROFILES.iterdir():
        if not profile_dir.is_dir():
            continue
        pending_skills = profile_dir / "pending" / "skills"
        if not pending_skills.exists():
            continue
        for f in sorted(pending_skills.glob("*.json")):
            if on_pending_created(f, notified, pending_map):
                save_notified(notified)
                save_pending_map(pending_map)


# ── Main loop ─────────────────────────────────────────────────────────────────

def watch() -> None:
    notified = load_notified()
    pending_map = load_pending_map()

    scan_existing(notified, pending_map)
    save_notified(notified)
    save_pending_map(pending_map)

    # Watch the real path (NIZAM_PROFILES), not HERMES_PROFILES whose subdirs are symlinks.
    # inotifywait -r does not follow symlinks, so watching ~/.hermes/profiles/ would
    # miss events in pending/ and skills/ (both are symlinks into nizam-os).
    log.info("watching %s (create + delete, recursive)", NIZAM_PROFILES)
    proc = subprocess.Popen(
        [
            "inotifywait", "-m", "-r",
            "-e", "create,moved_to,delete,moved_from",
            "--format", "%e %w%f",
            str(NIZAM_PROFILES),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )

    try:
        for line in proc.stdout:  # type: ignore[union-attr]
            line = line.strip()
            if not line:
                continue
            event_type, fullpath = line.split(" ", 1)
            is_create = event_type in ("CREATE", "MOVED_TO")
            is_delete = event_type in ("DELETE", "MOVED_FROM")

            if "/pending/skills/" in fullpath and fullpath.endswith(".json"):
                path = Path(fullpath)
                if is_create and path.exists():
                    if on_pending_created(path, notified, pending_map):
                        save_notified(notified)
                        save_pending_map(pending_map)
                elif is_delete:
                    on_pending_deleted(Path(fullpath).name, pending_map)
                    save_pending_map(pending_map)

            elif (fullpath.endswith("/SKILL.md") and is_create
                  and "/pending/" not in fullpath
                  and "/.archive/" not in fullpath):
                path = Path(fullpath)
                if path.exists():
                    on_skill_created(path, pending_map)
                    save_pending_map(pending_map)

    except KeyboardInterrupt:
        pass
    finally:
        proc.terminate()


if __name__ == "__main__":
    watch()
