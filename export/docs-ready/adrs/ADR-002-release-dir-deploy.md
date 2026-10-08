# ADR-002: Release-directory deploy, never edit live

> **Date:** 2026-09-26
> **Status:** ACCEPTED

## Context

The prior implementation symlinked systemd units and Hermes profile files directly into the git working tree. Editing a file, or switching git branches, immediately changed what was running. This forced an entire remediation phase (insulating live services before any reorganization could safely proceed) partway through a refactor attempt, and made ordinary development on the repo risky by default.

## Decision

Live services always run from `~/.local/share/nizam/current`, a symlink to a release directory under `~/.local/share/nizam/releases/<sha>`. `scripts/deploy.sh` builds a new release from a git ref, flips the `current` symlink atomically, applies a manifest of systemd/Hermes-config links, and restarts only units whose content changed. The git working tree itself is never live.

## Alternatives Considered

### Keep the repo as the live tree, be more careful

- **Pros:** Simplest possible setup, no extra deploy step.
- **Cons:** This is exactly the pattern that caused real live breakage in the prior iteration — "be more careful" is not a control, it's a hope.
- **Rejected because:** the cost of the release-dir pattern is small (one script) and it removes an entire class of mistake permanently, from day one, rather than retrofitting it after the first incident.

### Containerize each service (Docker)

- **Pros:** Strong isolation, a very standard deploy pattern.
- **Cons:** Adds real overhead on a 2 vCPU / 7.8 GB box, and this system runs on systemd already (for Hermes, for the metrics timers) — running some things in Docker and others as bare systemd units is more moving parts, not fewer, for no isolation benefit this system's threat model needs.
- **Rejected because:** the Feanor conventions this project loosely follows default to Docker, but that default assumes a team/CI context this one-person VPS project doesn't have (`export/00-START-HERE.md` explicitly notes this as a deliberate Feanor deviation).

## Consequences

- **Positive:** development on the repo (editing, branching, even a bad commit) never touches running agents. Rollback is a symlink flip, not a git revert-and-hope.
- **Negative / trade-offs:** one more script to maintain and get right; a deploy step between "committed" and "live" that must not be forgotten (mitigated by making it the only documented way to make anything live — see `RUNBOOK.md`).
- **Follow-up required:** none — this should be in place from the very first phase of the rebuild, not bolted on later.

## References

- `export/00-START-HERE.md` — non-negotiable design decision #2
- `export/BUGS-AND-GOTCHAS.md` #4 — the live-symlink coupling that motivated this
- `docs/ARCHITECTURE.md` — deploy model section
