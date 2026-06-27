#!/usr/bin/env python3
"""
Idempotent SAVE governance setup for a Hermes profile.

Run for any profile — safe to re-run, skips steps already done.

Steps:
  1. Patch config.yaml: skills.write_approval + skills.guard_agent_created → true
  2. Create skills/.audit.json as [] if missing
  3. Wire pending/ symlink: migrate ~/.hermes/profiles/{p}/pending/ → nizam-os + symlink

Usage:
  python3 scripts/save/setup-profile-governance.py admin
  python3 scripts/save/setup-profile-governance.py assistant
"""

import json
import subprocess
import sys
from pathlib import Path

NIZAM_PROFILES = Path(__file__).parent.parent.parent / "hermes" / "profiles"
HERMES_PROFILES = Path.home() / ".hermes" / "profiles"


def patch_config(profile: str) -> None:
    config = NIZAM_PROFILES / profile / "config.yaml"
    if not config.exists():
        print(f"  [skip] config.yaml not found for {profile}")
        return

    lines = config.read_text().splitlines(keepends=True)
    in_skills = False
    changed = False
    result = []

    for line in lines:
        stripped = line.rstrip()
        # Detect start/end of skills: block (ends when another top-level key appears)
        if stripped == "skills:":
            in_skills = True
        elif in_skills and stripped and not stripped.startswith(" "):
            in_skills = False

        if in_skills:
            if stripped == "  guard_agent_created: false":
                line = line.replace("false", "true", 1)
                changed = True
            elif stripped == "  write_approval: false":
                line = line.replace("false", "true", 1)
                changed = True

        result.append(line)

    if not changed:
        print(f"  [ok]   config.yaml already patched ({profile})")
    else:
        config.write_text("".join(result))
        print(f"  [done] config.yaml patched ({profile})")


def init_audit(profile: str) -> None:
    audit = NIZAM_PROFILES / profile / "skills" / ".audit.json"
    if audit.exists():
        print(f"  [ok]   .audit.json already exists ({profile})")
        return
    skills_dir = NIZAM_PROFILES / profile / "skills"
    if not skills_dir.exists():
        print(f"  [skip] skills dir missing for {profile} — create profile first")
        return
    audit.write_text("[]\n")
    print(f"  [done] .audit.json created ({profile})")


def wire_pending(profile: str) -> None:
    hermes_pending = HERMES_PROFILES / profile / "pending"
    nizam_pending = NIZAM_PROFILES / profile / "pending"

    if hermes_pending.is_symlink():
        print(f"  [ok]   pending/ already symlinked ({profile})")
        return

    nizam_pending.mkdir(parents=True, exist_ok=True)

    # Move contents if any exist in the real dir
    if hermes_pending.exists() and hermes_pending.is_dir():
        for item in hermes_pending.iterdir():
            dest = nizam_pending / item.name
            if not dest.exists():
                item.rename(dest)
        hermes_pending.rmdir()

    hermes_pending.symlink_to(nizam_pending)
    print(f"  [done] pending/ wired ({profile})")


def restart_gateway(profile: str) -> None:
    service = f"hermes-gateway-{profile}.service"
    result = subprocess.run(
        ["systemctl", "--user", "is-active", service],
        capture_output=True, text=True
    )
    if result.stdout.strip() == "active":
        subprocess.run(["systemctl", "--user", "restart", service])
        print(f"  [done] restarted {service}")
    else:
        print(f"  [skip] {service} not active — start it manually when ready")


def setup(profile: str) -> None:
    print(f"\n── {profile} ──────────────────────────────")
    patch_config(profile)
    init_audit(profile)
    wire_pending(profile)
    restart_gateway(profile)


def main() -> None:
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <profile> [profile2 ...]")
        print(f"       {sys.argv[0]} --all   (run for all profiles in nizam-os)")
        sys.exit(2)

    if sys.argv[1] == "--all":
        profiles = sorted(
            p.name for p in NIZAM_PROFILES.iterdir()
            if p.is_dir() and (p / "config.yaml").exists()
        )
    else:
        profiles = sys.argv[1:]

    for profile in profiles:
        setup(profile)

    print("\nDone.")


if __name__ == "__main__":
    main()
