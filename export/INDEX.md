# Nizam OS export — what's in this folder

This folder was exported on 2026-09-26 from the old VPS, before a full OS wipe
and rebuild. It currently sits at `~/nizam-os/export/` on the old box.

**Before the wipe, copy it off-box** — to a laptop, or push it to the new GitHub
repo. The wipe destroys it along with everything else.

**In the new setup**, this folder lives at the root of the brand-new
`nizam-os` repo, as `export/`. That puts its entry point at
`~/nizam-os/export/00-START-HERE.md`, which is the path
`nizam-dotfiles/docs/RUNBOOK.md` links to. It is read-only
reference material. Once cycle 1 is live, delete it in one commit; git history
keeps it.

## Read in this order

1. **`00-START-HERE.md`** — the executable rebuild plan, phases 0–7.
   Self-contained. Every new Claude Code session starts here.
2. **`docs-ready/`** — the finished doc set, copied into the new repo's `docs/`
   as the very first action. **Don't rewrite it.** It contains:
   - VISION, SRS, ARCHITECTURE, SCAFFOLD, SCHEMAS, SECURITY, RUNBOOK, TESTING,
     ROADMAP
   - `specs/`: 001-knowledge, 002-finance, 003-calc, 004-agent-runtime
   - `adrs/`: ADR-001 to ADR-007
   - `CLAUDE.md`, which goes to the new repo **root**, not `docs/`
   - `plan.toml`, which becomes `docs/plan.toml`. It holds **all 51 tickets
     for Phases 1–7** and passes Feanor's `plan.py check`. Every code ticket
     names its tests first — 292 named tests in total, including 69
     integration tests against real Postgres and 25 hypothesis property tests.

   Every open question from the owner interrogation is resolved.
3. **`BUGS-AND-GOTCHAS.md`** — ten concrete mistakes from the old system, each
   with the rule that prevents it.
4. Everything else is **reference material, not instructions.** Mine it for
   facts; don't copy it wholesale.

## Folder guide

| Folder | What it is | How to use it |
|---|---|---|
| `docs-ready/` | **The current doc set.** | Copy into the new repo (see above). Extend it — new ADRs, cycle-2 specs — never replace it. |
| `feanor-conventions/` | A full copy of the Feanor methodology: conventions, templates, and `scripts/plan.py`. | Coding conventions (`conventions/python`, `conventions/cross-stack`) apply as written, except the deviations listed in `docs-ready/SCAFFOLD.md`. Run tickets with `plan.py`. |
| `docs/` | The superseded doc set from 2026-09-10: SRS, PRD, SECURITY, THREAT-MODEL, `specs-new/`, and `reqs/raw.md` (the interrogation transcript). | Provenance, and the starting point for **cycle-2** specs (`specs-new/004` personal tracking, `006` investment, `007` self-maintenance). Don't build against it. |
| `docs/archive-reference/` | Older material: pre-rewrite `.bak` docs with concrete ports, channels and model names; July-era guides, plans and specs; the old business-agent design under `business-future/`; `nizam-dotfiles-archive-2026-09-26.tar.gz` (the old dotfiles `archive/` folder). | Facts only. **`business-future/` is out of scope — never build it.** |
| `code-reference/` | Old knowledge-service source, shared service wiring, and old migrations. | Understand the approach, then rewrite clean. The code carries the bug in BUGS #1, and has no tests. |
| `config-reference/` | Old LiteLLM, Hermes (secrets stripped to `${VAR}`), Redis, Promtail and logrotate configs. | The shape of the Hermes `config.yaml` and the LiteLLM routing. Old `command_allowlist` entries are **not** current — see `docs-ready/SECURITY.md`. |
| `systemd-reference/` | Old units. | `ExecStart` patterns only. The old names collided with `nizam-dotfiles` (`metrics-services`) — new units are `nizam-*`. No inline `#` comments (BUGS #5). |
| `scripts-reference/` | Old operational scripts. `setup/001-foundation.sh`, `002-hermes.sh` and `003-curator.sh` hold the real install commands that worked the first time. | Reference for `scripts/bootstrap.sh` and the Hermes setup steps. The inventory/env watchers and the skill watcher are **not** rebuilt. |
| `grafana-reference/` | Old dashboard JSON. | Panel ideas. Fix the profile-name regex to `admin\|curator\|assistant` (BUGS #9). |
| `hermes-profiles-reference/` | Nazim and Noor's old SOUL, AGENTS and memories. | Tone reference only. Rewrite AGENTS.md — the old one contradicted the security docs. |
| `OLD-README.md` | The old repo README. | Only the three-repo split idea survives. |

## Deliberately NOT in this export

- **Secrets.** No `.env` files, cookies, age keys, or literal secret values.
  The export was scanned; re-scan it before pushing:
  `gitleaks detect --no-git -s export/`.
- **Git history.** The old repo's `.git` dies with the wipe. Clone it elsewhere
  first if you want it.
- **Live DB data.** The rebuild starts empty, by owner decision. A snapshot
  exists at `~/.local/state/nizam/backups/pre-refactor.dump` on the old box —
  copy it off before the wipe only if you want it for reference.
- **Hermes application code.** Hermes is reinstalled fresh.
- **`nizam-vault` content.** It was test data only; the rebuild starts with an
  empty vault.

## Immediate next steps

1. Copy `~/nizam-os/export/` off the old VPS.
2. Make sure `~/nizam-dotfiles` is pushed to its remote. It is reused as-is,
   and its RUNBOOK now points here.
3. Wipe and reinstall the VPS with Ubuntu 24.04.
4. Follow `nizam-dotfiles/docs/RUNBOOK.md` → Machine setup. This is Phase 0.
5. Create a new, empty GitHub repo for `nizam-os`, clone it to `~/nizam-os`,
   and put this folder in it as `export/`.
6. Start Claude Code in `~/nizam-os` and say: "Read `export/00-START-HERE.md`
   and do the first action, then Phase 1."
