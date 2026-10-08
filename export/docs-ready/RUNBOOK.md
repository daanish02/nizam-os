---
title: Runbook — nizam-os (Cycle 1)
status: LOCKED
version: 1.0.0
date: 2026-09-26
---

# Runbook

Operational how-to. Absorbs what the prior iteration split across two guides (`001-foundation-guide.md`, `002-hermes-baseline-guide.md`) — see `export/00-START-HERE.md` Phases 1–5 for the actual build sequence; this document is the day-2 reference once cycle 1 is running.

## Deploy a change

```bash
scripts/deploy.sh --dry-run    # review what would change
scripts/deploy.sh              # build a release, flip `current`, restart changed units
```

Never edit anything under `/etc/systemd/system`, `~/.hermes/profiles/*/config.yaml`, or `~/.config/nizam/*.env` by hand — those are all managed by `deploy.sh` per `deploy/manifest.txt`. Edit the repo, then deploy.

## Rollback

```bash
scripts/deploy.sh --rollback
```

Flips `current` back to the previous release and re-applies its manifest. If something's badly wrong and even that's not responsive, the previous release directory under `~/.local/share/nizam/releases/` is untouched — you can always manually re-point the `current` symlink.

## Rotate a secret

1. Generate the new value: `openssl rand -hex 24` for passwords.
2. Change it at the source: `ALTER ROLE ... WITH PASSWORD ...` for a DB
   password, or the provider's dashboard for an API key.
3. Update `secrets/<name>.env`, the plaintext copy. It is gitignored.
4. Re-encrypt: `scripts/secrets.sh encrypt <name>`. This refreshes
   `secrets/<name>.env.enc`, which is what gets committed.
5. Push the value to where services actually read it:
   `scripts/deploy.sh --sync-secrets`. This decrypts into
   `~/.config/nizam/<name>.env`. **Skip this and nothing picks up the new
   value**, because services never read the repo copy.
6. Restart whatever consumes it: `sudo systemctl restart <unit>` or
   `systemctl --user restart hermes-gateway-<profile>`.
7. Check that the consumer actually works with the new value. Look in
   `journalctl -u <unit> -n 30` or `journalctl --user -u hermes-gateway-<profile> -n 30`
   for auth failures, and make one real call through it (e.g. ask Noor to
   search).

**Never update only one side.** A password changed at the source but not in the
consumer's env fails with a confusing auth error. This happened during the
original refactor attempt (`export/BUGS-AND-GOTCHAS.md` #1, second paragraph).

**The age key itself** lives at `~/.config/sops/age/keys.txt`. Keep an offline
copy. If it is lost, every `.env.enc` must be re-created from the plaintext
sources, so rotate all secrets.

## Approve (or decline) an agent's write

1. The agent shows a draft in its channel, then Hermes posts an approval prompt
   stating the effect.
2. Answer **once**: `/approve` or `/deny`. Never "session" or "always" — spec
   004 rule 6.
3. The prompt closes after 30 minutes unanswered, and nothing happens. The
   draft itself stays valid for 24 hours. Tell the agent "go ahead with that"
   and it re-raises the prompt. After 24 hours the agent must draft again.
4. If you approved and the agent reports `ALREADY_APPLIED`, the write already
   happened. Nothing is duplicated.

## Add a new Hermes agent

1. `agents/<name>/{SOUL.md,AGENTS.md,config.yaml}` — write these fresh for the new agent's actual mandate. Don't copy another agent's file and edit around the edges; that's how contradictions accumulate (`export/BUGS-AND-GOTCHAS.md` #7).
2. Decide its domain scope and add it to `nizam/core/auth.py`'s `SCOPES` map.
3. A new LiteLLM virtual key for it, so its spend is attributable.
4. `secrets/hermes-<name>.env` with its Discord bot token, virtual key, MCP bearer token.
5. Add manifest lines linking its config into `~/.hermes/profiles/<name>/`.
6. Deploy, then `hermes profile create <name>` / gateway install per Hermes's own docs.
7. Create its Discord bot application and channels manually (Discord has no API-first setup path worth automating for a handful of agents).
8. In its `config.yaml`, copy the standard `approvals` block from an existing
   agent: `mode: manual`, `gateway_timeout: 1800`, `cron_mode: deny`. Also
   enable the `nizam-approval` plugin. If the agent brings a **new domain**
   with write tools, add those tools to the plugin's write-tool list. Test E-30
   (spec 004) fails if you forget.

## Restore from backup

```bash
createdb nizam_restore_test
pg_restore -d nizam_restore_test ~/.local/state/nizam/backups/<date>.dump
# verify row counts, spot-check a few rows, then decide whether to actually
# restore into `nizam` itself or just confirm the backup is good
```

Test this restore path periodically even when nothing's wrong — an untested backup is a hope, not a backup.

## When LiteLLM is down

Deterministic writes (recording a transaction, saving a note's raw text) still succeed; anything needing the LLM (embedding, classification, natural-language parsing) is queued as `pending` and retried by a background job once LiteLLM is back (`SRS.md` §4.2, F-01). Check `systemctl status litellm-proxy` and `curl 127.0.0.1:4000/health/liveliness` first.

## When a knowledge search returns "transaction aborted" or similar

This is the exact bug documented in `export/BUGS-AND-GOTCHAS.md` #1 from the prior implementation. If it recurs: restart `nizam-mcp` to clear the poisoned connection (`sudo systemctl restart nizam-mcp`), then go fix the actual bug — a fallback query ran on the same connection as a failed one without a rollback. Don't just restart and move on; that's treating a symptom the codebase should already be tested against (see `TESTING.md`).

## Rebuild the knowledge index

The vault files are authoritative, and the index is a rebuildable cache. If
search results look wrong, or a write reported `INDEX_WRITE_FAILED` naming a
file path:

```bash
cd ~/.local/share/nizam/current && .venv/bin/python -m nizam jobs reindex
```

Run it with `~/.config/nizam/nizam-mcp.env` loaded, e.g. via
`systemd-run --uid=vazir -p EnvironmentFile=...`, or by exporting its values.
It:

- upserts every note it finds
- removes rows for deleted files
- adopts orphan files, logging each one — review those
- queues missing embeddings as pending

It is idempotent.

## Nazim's boundaries — what NOT to expect it to fix unattended

Nazim may restart one of these, **once**, then escalate in `#alerts`:

- `litellm-proxy`
- `nizam-mcp`
- `hermes-gateway-curator`
- `hermes-gateway-assistant`

It never touches Postgres, Redis, the observability stack, any
`nizam-dotfiles` unit, or its own gateway (`Restart=always` covers that). It
makes no file edits. If Postgres is down, Nazim reports it and waits for you.
That is correct behaviour, not a gap. Enforcement details are in `SECURITY.md`.

## Checking system health without logging in

Grafana (via Tailscale) has the service-up/down, LLM spend, and error-rate panels. Ask Nazim directly in `#admin` — it has read-only tools to explain its own configuration and report status (SRS CN.04.4 — deferred to cycle 2 for the fuller self-maintenance capability, but Nazim's basic status reporting is cycle 1).
