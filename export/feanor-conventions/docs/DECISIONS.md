---
type: reference
title: Feanor Design Decisions
description: Why Feanor is built the way it is — the reasoning behind its structural choices, so a future maintainer can tell a deliberate constraint from an accident.
applies_to: [maintainer]
tags: [docs, maintainer, decisions, rationale, architecture]
---

# Design Decisions

Rationale for Feanor's own structure. Without this, a future maintainer cannot distinguish a deliberate constraint from an accident, and "simplifies" the load-bearing parts.

These are decisions about **Feanor**. Decisions about a *target project* are ADRs in that project's `docs/adrs/`, per `meta/adrs.md`.

---

## D-001 — Installed per project, not globally

Feanor is installed into each project rather than living in `~/.config` and being reached for globally.

**Why:** a project built under one set of standards and audited a year later under a silently-updated global set produces meaningless audit results. Per-project installation means the version that built the code is the version present when it is reviewed.

**Revised 2026-09-08 — installed by the `lattice` CLI to a gitignored `skills/feanor/`, replacing `install.sh`'s git-subtree copy into a tracked `./feanor/`.** See D-013 for why, and for the cost this decision gave up.

## D-002 — Never on `main`

Feanor is not tracked by the project at all, so it reaches no branch.

**Why:** it is development-time tooling. Interrogation methods, phase prompts, and micro-standards are not part of the product, and shipping them to production means shipping internal process documentation to whoever can read the repo.

**Revised 2026-09-08:** originally this was a tracked `./feanor/` kept off `main` by a pre-commit hook, a CI check, and a manual strip step before release — three layers guarding an invariant that was still one `--no-verify` away from breaking. Under the CLI install `skills/` is gitignored, so the invariant holds by construction: there is nothing to strip, nothing to guard, and no way to get it wrong. `.feanor/` (plan, audit trail, state) remains tracked on every branch — it is the record of how the code came to be, and it belongs to whoever inherits the project.

The hook slot freed by this now enforces something that was never enforced at all: no direct commits to `main` or `qa` (D-013).

## D-003 — JIT retrieval with a hard cap

Conventions are retrieved per ticket by tag and path, capped at ten files.

**Why:** the two obvious approaches both fail. Load everything and the model attends to none of it — the standards are present and ignored. Load nothing and it invents a different convention per file. A small, relevant set is the only thing that actually changes output.

**Consequence:** convention files must be small, single-topic, and carry a genuinely descriptive `description`, because that field is what the resolver reads. This is why line budgets are enforced rather than advisory.

**Revised 2026-09-07:** cap raised 6 → 10, with security conventions ranked first and never dropped. At six, a ticket carrying the three mandatory tags plus a language plus a domain tag routinely overflowed, and the priority ladder dropped security rules to make room — the exact opposite of what should be sacrificed.

## D-004 — Deterministic steps become scripts, not prose

A step with one mechanical outcome is a real file in `scripts/`; a step needing judgment stays prose.

**Why:** prose describing a mechanical step is a seam where two runs diverge. A code block in Markdown is better but still re-derived each run, and re-derivation is where a flag gets dropped. A tested script cannot reintroduce a bug that was already fixed in it. This was learned concretely: `uv init` described in prose silently produced the wrong directory layout.

**Corollary:** do not fake determinism where none exists. Forcing an audit's findings or a PRD's wording into a script produces worse output than letting the model judge.

## D-005 — Only `plan.py` can mark a ticket done

Verification runs through `plan.py verify`, which executes the command without a shell, records the real exit code, and sets `tests_passing`. `plan.py done` refuses without it.

**Why:** the engine's entire claim is evidence-based completion. Any path that lets the model assert its own success removes that. This was not theoretical — the previous implementation piped the command into `tee` and recorded the pipe's exit status, so **every** ticket passed regardless of test outcome for as long as that code existed.

**Consequence:** `verification_command` is a single argv line with no shell operators, and `working_dir` replaces a leading `cd`. Slightly less convenient, and the convenience is what made it exploitable.

## D-006 — No `status` field in frontmatter

Frontmatter is `type`, `title`, `description`, `applies_to`, `tags`. There is deliberately no `status: draft|stable|deprecated`.

**Why:** every file in the corpus is live and normative. A status that reads `stable` on all of them carries no information while costing a line in every file and a check in the linter. A convention that no longer holds is **deleted**, because an agent that JIT-loads a file marked `deprecated` will follow it anyway — the marker protects the human reader and not the actual consumer.

## D-007 — Three capability tiers, not two

Baseline / conditional / optional, rather than mandatory / optional.

**Why:** the middle tier behaves differently from both neighbours. API design conventions are not optional for a system with an API, but they also are not universal. Collapsing them into "optional" invites declining something that cannot meaningfully be declined; collapsing them into "baseline" applies database rules to a CLI. The distinction also maps directly onto how scope is explained to a client. See [CAPABILITIES.md](./CAPABILITIES.md).

## D-008 — Capabilities are machine-readable, not just documented

The tier decisions land in `.feanor/profile.toml` in each target project, read by the resolver, the planner, and the validation agent.

**Why:** a tier model that exists only as prose is a policy nobody enforces. The decisive case is `/audit`: without a declared profile it can only inspect what exists, so it cannot distinguish "no caching because the project opted out" from "no caching because someone forgot." With a profile it checks both directions.

**Consequence:** the target project's client-facing `docs/CAPABILITIES.md` is generated from the profile, so what the client is told and what the agents enforce share one source.

## D-009 — Logging is baseline, metrics and tracing are optional

`observability-logging.md` covers logging only. Metrics and tracing are separate, opt-in conventions.

**Why:** they are different kinds of commitment. Structured logging with redaction costs only doing it correctly, and nothing is diagnosable without it. Metrics require a collector, storage, dashboards, alert routing, and a human who looks at them — an operational commitment a project can legitimately decline. Bundling them meant a single sentence in the Go section was the entire metrics guidance for all three languages.

**Split into two, not one:** metrics and tracing are independently wanted. Plenty of teams run metrics with no tracing.

## D-011 — Mechanical checks block, with a recorded override

Every check script refuses the action on failure and accepts `--override "<reason>"`, which proceeds and logs the reason to `.feanor/logs/overrides.log`.

**Why not report-only:** a script whose output the agent may ignore leaves liability roughly where it was. The only part of Feanor that has never silently failed is `plan.py done`, precisely because it refuses.

**Why not block absolutely:** a false positive in a check would halt all work until the check itself is fixed, and the predictable response to that is deleting the check rather than fixing it. An override that must be typed with a reason, and that leaves a record, keeps the gate honest without making it brittle.

**Consequence:** warnings never affect exit codes. A gate that blocks on something uncertain gets ignored exactly like a noisy alert, and then the real findings go unread with it.

## D-012 — Script the result, never the judgment

The determinism push converted preconditions, ticket validation, registration consistency, and a subset of convention compliance into gates. It deliberately left alone: spec and PRD content, ticket scoping, whether an abstraction is right, audit severity, and whether a requirement answer is vague.

**Why the boundary matters as much as the conversions.** A sweep of the conventions produced ~52 candidate rules; six were rejected as not mechanically decidable — "the ownership predicate is in the WHERE clause" needs to understand the query's intent, "no stuttering in Go names" is a style judgment. Implementing those would produce false positives, and a checker people learn to ignore is worse than no checker, because the true findings get ignored alongside them.

The test is `determinism-standard.md`'s existing one: if the same input must produce a byte-identical answer, it is a gate. If two competent engineers could reasonably disagree, it stays prose and stays with the model.

## D-010 — Security is a gate, not a document

Security requirements are elicited in `/reqs` as abuse cases, traced through zigzag validation, threat-modelled in `/hld`, ticketed in `/plan`, and scanned in `/audit`.

**Why:** a control nobody asked for has nothing to trace to, so it is dropped under time pressure and nobody can tell afterwards whether that was a decision or an oversight. Making `SECURITY.md` optional-by-judgment meant the projects most needing it were exactly those whose architect was moving fastest.

**Consequence:** `SECURITY.md` and `THREAT-MODEL.md` are mandatory on a deterministic trigger, not an assessment of whether the project "feels" security-sensitive.

## D-013 — One install path: the `lattice` CLI, not `install.sh`

`install.sh` is retired. Feanor is installed and updated only by `lattice add feanor` / `lattice update feanor`, which extract to a gitignored `skills/feanor/`.

**Why:** two install paths existed and only one of them enforced anything. `install.sh` refused to run on `main` and installed verified branch-guard hooks; `lattice add` installed no hooks and had no branch guard at all. `README.md` promised the enforcement unconditionally — "installs and **verifies** the branch-guard hooks… does not silently continue with enforcement missing" — while the CLI, the path actually used, silently continued with enforcement missing. A full live run confirmed it: `.git/hooks/` was empty, and the project's entire history landed on `main`.

A guarantee that holds on one of two paths is not a guarantee. Keeping both in sync was the maintenance burden that produced the gap in the first place, so the fix is one path rather than a second copy of the enforcement.

**What it cost — stated plainly:** D-001's original rationale was that conventions are *versioned with the code they governed*, because `feanor/` was committed. A gitignored `skills/` gives that up: checking out a year-old commit no longer reproduces the conventions in force at the time. `.feanor/` (plan, audit trail, verification log) is still tracked and still records what was decided and verified, but the convention *text* is not recoverable from the repo alone — only the pinned version recorded in `.feanor/state/`. This is a real regression in auditability, accepted because the alternative was enforcement that provably did not run.

**What it bought:** the "never on `main`" invariant now holds by construction rather than by three cooperating layers (D-002), and the freed `pre-commit` slot enforces the rule that was violated in practice — no direct commits to `main` or `qa`.

**Mechanism:** a skill declares its hooks in `lattice-hooks.json`; the CLI installs them, reports each one, and refuses to overwrite a foreign hook, naming the file to wire in by hand instead. Generic, so lattice stays skill-agnostic and the hook's source stays with whoever maintains it.
