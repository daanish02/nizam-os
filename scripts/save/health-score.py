#!/usr/bin/env -S uv run
# /// script
# requires-python = ">=3.12"
# dependencies = []
# ///
"""
Reads .usage.json from all Hermes profile skill dirs and outputs a health score
table. Optionally writes state flags back to .usage.json.

Health score (0–100):
  Recency  (40 pts): last_used_at within 7d→40, 30d→20, 60d→5, never→0
  Volume   (30 pts): use_count ≥10→30, ≥5→20, ≥1→10, 0→0
  Churn    (30 pts): patch_count/max(use_count,1) <0.5→30, <1→15, ≥1→0

Flags written back (--write flag required):
  score < 30 AND use_count ≥ 3  → state: needs_review
  score < 10                     → state: archive_candidate
  last_used_at > 90d (or never used + created > 30d) → state: stale

Usage:
  python3 scripts/save/health-score.py              # table only
  python3 scripts/save/health-score.py --write      # table + write state flags
  python3 scripts/save/health-score.py --profile admin  # single profile
"""

import json
import sys
from datetime import datetime, timezone
from pathlib import Path

NIZAM_OS = Path(__file__).parent.parent.parent
PROFILES_DIR = NIZAM_OS / "hermes" / "profiles"

STALE_DAYS = 90
STALE_NEVER_DAYS = 30  # never-used skill stale after this many days since creation


def score(entry: dict, now: datetime) -> tuple[int, str]:
    use_count = entry.get("use_count") or 0
    patch_count = entry.get("patch_count") or 0
    last_used_raw = entry.get("last_used_at")
    created_raw = entry.get("created_at")

    # Recency
    if last_used_raw and use_count > 0:
        try:
            lu = datetime.fromisoformat(last_used_raw.rstrip("Z")).replace(tzinfo=timezone.utc)
            days = (now - lu).days
        except Exception:
            days = 9999
        if days <= 7:
            recency = 40
        elif days <= 30:
            recency = 20
        elif days <= 60:
            recency = 5
        else:
            recency = 0
    else:
        recency = 0
        days = 9999

    # Volume
    if use_count >= 10:
        volume = 30
    elif use_count >= 5:
        volume = 20
    elif use_count >= 1:
        volume = 10
    else:
        volume = 0

    # Churn
    ratio = patch_count / max(use_count, 1)
    if ratio < 0.5:
        churn = 30
    elif ratio < 1.0:
        churn = 15
    else:
        churn = 0

    total = recency + volume + churn

    # Determine flag
    flag = "ok"
    if use_count == 0:
        if created_raw:
            try:
                cr = datetime.fromisoformat(created_raw.rstrip("Z")).replace(tzinfo=timezone.utc)
                age_days = (now - cr).days
            except Exception:
                age_days = 0
            if age_days > STALE_NEVER_DAYS:
                flag = "stale"
        # else: brand new, no flag yet
    elif days > STALE_DAYS:
        flag = "stale"
    elif total < 10:
        flag = "archive_candidate"
    elif total < 30 and use_count >= 3:
        flag = "needs_review"

    return total, flag


def load_profile_skills(profile_dir: Path) -> dict[str, dict]:
    usage_file = profile_dir / "skills" / ".usage.json"
    if not usage_file.exists():
        return {}
    try:
        return json.loads(usage_file.read_text())
    except Exception:
        return {}


def write_state(profile_dir: Path, skill_name: str, new_state: str) -> None:
    usage_file = profile_dir / "skills" / ".usage.json"
    if not usage_file.exists():
        return
    try:
        data = json.loads(usage_file.read_text())
        if skill_name in data:
            data[skill_name]["state"] = new_state
            usage_file.write_text(json.dumps(data, indent=2) + "\n")
    except Exception as e:
        print(f"  WARNING: could not write state for {skill_name}: {e}", file=sys.stderr)


def main() -> None:
    write_back = "--write" in sys.argv
    filter_profile = None
    if "--profile" in sys.argv:
        idx = sys.argv.index("--profile")
        if idx + 1 < len(sys.argv):
            filter_profile = sys.argv[idx + 1]

    now = datetime.now(timezone.utc)

    profiles = sorted(PROFILES_DIR.iterdir()) if PROFILES_DIR.exists() else []

    rows: list[tuple[str, str, int, str, int, int, str]] = []
    # (profile, skill, score, flag, use_count, patch_count, last_used)

    for profile_dir in profiles:
        if not profile_dir.is_dir():
            continue
        if filter_profile and profile_dir.name != filter_profile:
            continue

        skills = load_profile_skills(profile_dir)
        for skill_name, entry in skills.items():
            s, flag = score(entry, now)
            lu = (entry.get("last_used_at") or "never")[:10]
            rows.append((
                profile_dir.name,
                skill_name,
                s,
                flag,
                entry.get("use_count") or 0,
                entry.get("patch_count") or 0,
                lu,
            ))

    if not rows:
        print("No skills found.")
        return

    rows.sort(key=lambda r: r[2])  # sort by score ascending (worst first)

    FLAG_ICONS = {
        "ok":                "✅",
        "needs_review":      "⚠️ ",
        "archive_candidate": "🔴",
        "stale":             "💤",
    }

    header = f"{'Profile':<12} {'Skill':<35} {'Score':>5} {'Flag':<18} {'Uses':>5} {'Patches':>7} {'Last Used':<12}"
    print(header)
    print("-" * len(header))

    for profile, skill, s, flag, uses, patches, lu in rows:
        icon = FLAG_ICONS.get(flag, "  ")
        print(f"{profile:<12} {skill:<35} {s:>5} {icon} {flag:<14} {uses:>5} {patches:>7} {lu:<12}")

        if write_back and flag != "ok":
            # Only update state if it's currently 'active' (don't overwrite existing flags)
            profile_dir = PROFILES_DIR / profile
            usage_file = profile_dir / "skills" / ".usage.json"
            try:
                data = json.loads(usage_file.read_text())
                if skill in data and data[skill].get("state") == "active":
                    write_state(profile_dir, skill, flag)
                    print(f"  → wrote state={flag} for {skill}")
            except Exception:
                pass

    if write_back:
        print("\nState flags written to .usage.json where skill was 'active'.")
    else:
        print("\nRun with --write to persist state flags to .usage.json.")


if __name__ == "__main__":
    main()
