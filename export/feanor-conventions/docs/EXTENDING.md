---
type: reference
title: Extending Feanor — Where To Register What
description: Every registration point for a new convention, script, template, agent, workflow, meta method, or maintainer doc — what to update, in what order, and how to verify nothing was missed.
applies_to: [maintainer]
tags: [docs, maintainer, extending, registration, checklist]
---

# Extending Feanor

Adding a file is never enough. Feanor finds things through catalogs and a tag map, so an unregistered file exists on disk and is invisible to every agent — the worst failure mode, because nothing errors. It just quietly never applies.

**The universal last step, whatever you added:**

```bash
uv run feanor/scripts/reindex.py                     # regenerate directory catalogs
uv run feanor/scripts/validate-okf.py                # frontmatter + tag map integrity
uv run feanor/scripts/resolve-context.py --validate  # every tag resolves to a real file
```

All three must pass. The second and third are what catch an unregistered or mis-registered file.

---

## Quick reference

| You added… | Register it in |
| :--- | :--- |
| A convention (`conventions/**/*.md`) | `conventions/tags.toml` **←the one people forget**, `conventions/index.md` |
| An optional/conditional capability | plus `docs/CAPABILITIES.md`, `scripts/write-profile.py` |
| A script (`scripts/*`) | `scripts/index.md`, `.feanor-manifest.yaml`, the agent that calls it |
| A template (`templates/**`) | `templates/index.md` or `templates/high-level-docs/index.md`, the agent that writes it |
| An agent (`agents/*.md`) | `agents/index.md`, `meta/command-router.md`, `.feanor-manifest.yaml`, the workflow |
| A workflow (`workflows/*.md`) | `workflows/index.md`, root `index.md` if it is an entry point |
| A meta method (`meta/*.md`) | `meta/index.md`, `conventions/tags.toml` if agents load it, the agent that follows it |
| A maintainer doc (`docs/*.md`) | `docs/index.md` — **and nothing else, ever** |

---

## A new convention

The most common addition, and the one with the most registration points.

1. **Write the file** in the right directory — `conventions/cross-stack/` if it applies to more than one language, `conventions/<lang>/` if not. Follow `meta/determinism-standard.md`: rule-first, no preamble, line budget, and a `description` that states what rules live there and when to load it. That description is what the resolver reads.
2. **Add it to `conventions/tags.toml`.** Without this the file is unreachable except by accidental path-matching:
   ```toml
   [tags.your-topic]
   files = ["conventions/cross-stack/your-topic.md"]
   aliases = ["synonym", "other-name"]
   priority = 4                    # 1 security · 2 principles · 3 language · 4 domain · 5 devops
   language_qualified = true       # only if go-/python-/nextjs- prefixed forms should resolve here
   requires_capability = "thing"   # only for an optional-tier capability
   ```
3. **Add a line to `conventions/index.md`.** `reindex.py` does *not* rewrite existing catalogs — it only creates missing ones — so this prose catalog is hand-maintained on purpose. The Planner reads it in full.
4. **Cross-reference from related conventions.** A "Related:" line at the bottom of neighbouring files. This is how an agent that loaded one file discovers the adjacent one.
5. **If it is a capability, not a baseline rule** — see the next section.
6. **Verify** with the three commands above, then check what it actually loads:
   ```bash
   uv run feanor/scripts/resolve-context.py --tags your-topic --files backend/app/x.py --explain
   ```

## A new capability (optional or conditional tier)

On top of the convention steps:

1. **Decide the tier in `docs/CAPABILITIES.md` first**, before writing anything. Baseline needs a strong argument — the floor should rise slowly. Add a row to the Tier 2 or Tier 3 table, and for Tier 3 give an **honest cost**, not just the benefit.
2. **Add the flag to `scripts/write-profile.py`** — a key in the `OPTIONAL` dict (with its convention path) or `CONDITIONAL` dict (with the conventions its trigger makes mandatory).
3. **Set `requires_capability` in `tags.toml`** so the resolver gates it.
4. **Add the elicitation question to `meta/requirements-checklist.md` §2.7** — framed as an outcome ("who finds out when this breaks?"), never as a technology. `/reqs` must not present a technology menu.
5. Until the convention exists, `write-profile.py` refuses to enable the capability. That is deliberate: enabling it would leave `/exec` with nothing to load, so the implementation would be improvised.

## A new script

1. **Write it in `scripts/`**, with PEP 723 inline metadata if Python (`# /// script`) so `uv run` needs no install. Run it against a scratch directory before committing — `meta/determinism-standard.md` requires scripts be actually executed, not just written and assumed correct.
2. **Add it to `scripts/index.md`** with one line saying what it does and who calls it.
3. **Add it to `.feanor-manifest.yaml`** under `validation_scripts` if it is maintenance tooling.
4. **Wire it into the agent prompt that calls it.** A script nothing invokes is dead weight — and the point of a script over a prose code block is that the agent stops re-deriving the steps.
5. Scripts are **not** conventions. They never go in `tags.toml`.

## A new template

1. **Write it in `templates/`** (or `templates/high-level-docs/` for a `docs/` artifact), with `{{PLACEHOLDER}}` fields.
2. **Add it to the relevant index.** For high-level docs this means the selection table in `templates/high-level-docs/index.md` — under *Conditionally mandatory* if a deterministic trigger should force it, or *Select if applicable* with the condition for generating it.
3. **Tell the generating agent to read it** — usually `agents/architect-agent.md`. A template no agent reads is never used.

## A new agent or command

1. **Write `agents/<name>-agent.md`** with the phase's system prompt.
2. **`meta/command-router.md`** — add a row to §1's mapping table *and* a precondition check to §2. A command with no precondition can run out of order.
3. **`agents/index.md`** and **`.feanor-manifest.yaml`** `supported_commands`.
4. **The workflow file** in `workflows/` that sequences it.

These four must agree. They have drifted before: the manifest and `brownfield-standardize.md` both routed to an `intake-agent.md` that did not exist, and nothing detected it because no check compares them.

## A new maintainer doc

Add it to `docs/index.md`. **Nothing else.** Never add a `docs/` file to `tags.toml` — `meta/context-resolver.md` §2 forbids the resolver from returning anything under `docs/`, because it is descriptive rather than normative and would spend execution context on material that cannot change the code.

---

## This is now enforced

Registration used to be spread across catalogs, a tag map, a manifest, and agent prompts with only frontmatter machine-verified — so a new agent missing from the router, or a template no agent reads, passed every check. Every drift bug found in the 2026-09-07 audit was that shape.

`scripts/check-registration.py` now closes it, and runs inside `check-all.sh` and the pre-commit hook. It cross-checks the manifest against the router against `agents/`, verifies every catalog lists its directory's files, flags templates nothing references, and resolves every relative markdown link — the check that would have caught `intake-agent.md`.

It proved itself on first run by finding six real gaps, including a `meta/` file added minutes earlier and two scripts that had been unlisted for far longer.

**Still not machine-verified:** whether a convention's *content* is correct, whether an agent prompt actually follows the method it cites, and whether a template's fields make sense. Those need judgment, and stay with review.
