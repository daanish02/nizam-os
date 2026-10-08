# nizam-os — rules for coding agents

Personal agent OS for one person (Danish), on one VPS. Discord is the only
interface. Hermes agents call one MCP daemon (`nizam-mcp`). LiteLLM routes to
OpenRouter (DeepSeek). Postgres holds data; `~/nizam-vault` holds notes.

## Read before changing anything
- `docs/SCAFFOLD.md` — where things go. Anything not listed there doesn't
  belong.
- `docs/ARCHITECTURE.md` — components, ports, units, config.
- `docs/specs/004-agent-runtime.md` — the approval gate every write obeys.
- The spec for the domain you're touching: `docs/specs/NNN-*.md`. **Specs are
  the target. If code and spec disagree, change the code** — unless the spec is
  wrong, in which case raise it with Danish first.

## Hard rules
- **Never run `git commit`.** Stop, summarise the change, and tell Danish it's
  ready. He commits.
- **Never edit live.** Nothing under `/etc/systemd`, `~/.hermes/profiles`,
  `~/.config/nizam` or `~/.local/share/nizam` is edited by hand. Change the
  repo, then Danish commits, then `scripts/deploy.sh`.
- **Never put a secret in a tracked file**, a log line, a commit or chat.
  Plaintext lives only in `secrets/*.env` (gitignored) and `~/.config/nizam/`.
  Run `scripts/secrets.sh check` before saying you're done.
- **Keep DeepSeek models** in every LiteLLM and Hermes config. Don't swap in
  another provider's models.
- **Every write is two-pass** with a signed `draft_token` (`nizam/core/approval.py`).
  Any new write tool must also be added to the Hermes `nizam-approval` plugin's
  write-tool list. Test E-30 enforces this.
- **Never retry a query on a failed transaction.** Roll back first
  (`core.db.transaction()` does). See `export/BUGS-AND-GOTCHAS.md` #1.
- **Money is integer sub-units with half-even rounding, always via
  `nizam/calc/`.** Never use floats.
- **No inline `#` comments on systemd directive lines.**
- **Unit names:** `litellm-proxy` or `nizam-*` only. `metrics-*` belongs to
  `nizam-dotfiles`.
- **Cycle 1 only:** knowledge, finance and calc. Don't build tasks, habits,
  journal, investment or anything business-related.

## Workflow
- Tickets live in `docs/plan.toml`. Run them with
  `uv run --with tomlkit --with rich python export/feanor-conventions/scripts/plan.py next|verify|done`.
- **TDD, always.** Write the ticket's named tests first, watch them fail, then
  write the code. `docs/TESTING.md` has the loop, fixtures, markers and
  hypothesis profiles.
- `bash scripts/check.sh` (fast) must pass on every ticket. Tickets that touch
  the DB verify with `bash scripts/check.sh --all`, which adds the `[slow]`
  Postgres tests and the **coverage gate** (core/calc/finance >= 90%,
  overall >= 80%).
- A spec acceptance ID (A-, B-, C-, E-xx) changed means its named test changes
  in the same commit.
- Conventions: `export/feanor-conventions/conventions/` (python/,
  cross-stack/). Deviations are listed in `docs/SCAFFOLD.md`.
- If unsure about an integration, port, model, money rule or religious rule,
  **ask Danish** rather than guessing.
