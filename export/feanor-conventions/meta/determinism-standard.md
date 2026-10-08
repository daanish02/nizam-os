---
type: meta
title: Determinism Standard
description: Deterministic steps get literal code blocks, not prose descriptions; judgment steps stay prose. Also governs convention file authoring — verbatim boilerplate blocks, description field quality, and file length targets.
applies_to: [agents, meta, conventions]
tags: [determinism, code-blocks, standards, convention-authoring]
---

# Determinism Standard

## Rule

Any step with exactly one correct mechanical outcome — no interpretation, no judgment call — **MUST** be expressed as a literal, runnable code block (bash/python/json/yaml as appropriate), not a prose description for the agent to reinterpret. A prose description of a deterministic step is a seam where two runs can silently produce different results; a code block has no seam.

Any step requiring judgment (what an audit finds wrong, how to scope a ticket, whether an answer was vague, how to word a PRD section) **MUST NOT** be forced into code — that's what the LLM is for. Don't fake determinism where none exists.

## How to tell which is which

Ask: "if I ran this same input through this step twice, must the output be byte-identical?"

- Yes → code block. Examples: writing a fixed-shape JSON/YAML marker, appending a section to a log file, checking whether a file exists, running a test command, scaffolding a directory tree once names are chosen.
- No → prose. Examples: deciding if a codebase is "structurally compliant," drafting PRD prose, choosing which ticket a bug belongs to, judging whether an answer needs a follow-up question.

Many steps are a mix — the surrounding decision is judgment, the resulting action is mechanical. Keep the judgment in prose and pull only the mechanical result into a code block, right where it happens. Don't split them into far-apart sections.

## Format

- Fenced code blocks with a real language tag (`bash`, `json`, `yaml`, `python`) — never a plain unlabeled block for something meant to be executed literally.
- Placeholders inside a code block use the same `{{UPPER_SNAKE}}` convention as the rest of Feanor's templates, so a literal block and a fill-in-the-blanks template look consistent.
- A code block that writes/patches a file should be complete enough to run as-is (real command, real path, real key names) — not pseudocode dressed up in a code fence.

## A Step Further: Real Script Files, Not Just Code Blocks

A code block in a markdown file still has to be _re-derived_ — an agent reads it and reproduces it, which is one more place a subtle error can creep in (a dropped flag, a wrong path) even when the block itself is correct. Where the deterministic step is **Feanor's own tooling** (not target-project source code — see the distinction below), it belongs in a real, tested file under `scripts/`, called directly, not retyped from a comment each run. This is how `scripts/scaffold/*.sh`, `plan.py`, `resolve-context.py`, `append-audit-report.sh`, and `write-state-marker.py` are built — each was actually run against a scratch directory to verify it, not just written and assumed correct. `architect-agent.md`'s `/scaffold` directive is the concrete example of why this matters: an earlier version described `uv init` as a prose step, and a real dry run found that the naive invocation silently produces the wrong directory layout — a bug a tested script file can't reintroduce, because it was already run and checked.

**Feanor's own tooling** (operates on `.feanor/` state, scaffolds a project, patches Feanor's bookkeeping) → real script file in `scripts/`, referenced by the engine.
**Target-project source code** (a logging handler, an error class, application logic meant to ship as part of the built product) → stays as a literal code block in the relevant `conventions/*.md` file, since it needs to be copied _into_ the project as real source, not executed by Feanor itself.

## The Enforcement Ladder

Writing a script is only half of it. What decides how much liability actually goes away is whether anything makes the script run.

| Level | Mechanism | Residual liability |
| :--- | :--- | :--- |
| **3 — Gate** | The script refuses the action. `plan.py done` cannot be talked out of it. | Near zero |
| **2 — Check** | The script reports; the agent decides what to do | The agent may not run it, or may ignore the output |
| **1 — Prose** | An instruction in a markdown file | Full model discretion, and silent when skipped |

**A mechanical step belongs at level 3.** A check nothing invokes is level 1 wearing a script's clothing — which is why `scripts/check-all.sh` is wired into the pre-commit hook rather than left for someone to remember.

Feanor's gates: `check-preconditions.py` (phase may run), `plan.py verify`/`done`/`next` (ticket is verified and valid), `resolve-context.py` (which conventions load), `validate-okf.py` (frontmatter and tag map), `check-registration.py` (internal references agree), `audit-mechanical.py` (target-project conventions).

### The override convention

Every gate accepts `--override "<reason>"`: it proceeds and appends the reason to `.feanor/logs/overrides.log`.

This exists because a **wrong check must never permanently halt real work** — that is how a blocking gate gets deleted instead of fixed. But the bypass is deliberate and leaves a trail, so it is a decision someone made rather than a step quietly skipped. Warnings never block: a gate that stops work over something uncertain gets ignored the same way a noisy alert does.

## Where this applies

Every `agents/*.md` step that writes a marker, a JSON field, a log entry, or scaffolds a fixed structure. Every `meta/command-router.md` precondition check. Every `workflows/*.md` step describing a mechanical file operation. Existing files predating this standard are converted incrementally — new files follow it from the start.

## Convention File Authoring Standard

### Verbatim vs. guidance

- Code that is byte-identical across projects (setup files, boilerplate types, middleware stubs) → MUST include a `## Boilerplate` block with the exact file content AND a corresponding script in `scripts/scaffold/` that emits it.
- Guidance (principles, rationale, tradeoffs, decision rules) → prose only. No fake code blocks.

**Test:** "Would two engineers independently produce the same file from this convention?"

- Yes → verbatim block required. If a script can produce it, the script is the authoritative source; the block in the convention file is the reference copy.
- No → prose only.

### Content optimisation mandate

- Rule-first: no introductory paragraphs. Lead with the rule or constraint, not the motivation.
- Bullet lists over paragraphs wherever the content is a list of items or conditions.
- Prose that does not change engineer behaviour is cut.
- Maximum 3 heading levels (`##`, `###`, `####`). Do not use `#####` or deeper.
- File length targets:
  - `cross-stack/` files: ≤ 200 lines
  - Language-specific files (`go/`, `python/`, `nextjs/`): ≤ 120 lines
  - `typescript/` files: ≤ 100 lines

### Frontmatter `description` field mandate

The `description` field must answer "is this the right file to load?" — one LLM-facing sentence stating what rules live here, which languages they apply to, and when to load this file.

- Bad: `"Authentication conventions."`
- Good: `"httpOnly cookie policy, server-side RBAC, and token rules — applies to Go, Python, and TypeScript equally."`

The description is the first thing the Context Resolver reads when deciding whether to include a file. If it doesn't state the rules and the scope in one sentence, it fails its job.

---

## Interpreter Availability (learned from a real dry run)

A `python`/`python3`/`bash` code block in this repo is a _reference implementation_ of the exact transformation, not a guarantee that interpreter is on `PATH` in whatever environment executes it — a real dry run hit `python3: command not found` on a Windows machine that had `uv` installed but no bare Python shim. When applying one of these blocks:

- If you (the agent) have a direct file-edit tool, prefer applying the transformation with that tool directly over shelling out — for a single-field JSON patch or an append-only file write, there's no reason to depend on an external interpreter existing at all.
- **Every Feanor script declaring PEP 723 dependencies guards its imports** via `_gate.require_uv_run()`: run with a bare interpreter it prints the exact `uv run` command and exits **2** (distinct from 1, a gate failure), rather than a `ModuleNotFoundError` traceback. That traceback's obvious "fix" is `pip install`, and in a real run an agent did exactly that — abandoning `uv` and polluting the environment, so the next run's behaviour depended on machine state instead of the script's own header. The guard fires only when a dependency is genuinely missing, so it costs nothing when the script can run.
- If you do need to shell out, prefer the target project's own toolchain over assuming a bare system interpreter exists — the project's toolchain is guaranteed present once `/scaffold` has run; a bare system interpreter isn't guaranteed present anywhere. In a `uv`-managed project this is just `uv run script.py` — `uv run` executes a `.py` file directly (no `python`/`python3` needed in front of it) and, via inline PEP 723 metadata (`# /// script` blocks) or `uv run -m module`, can run a one-off script with its own dependencies or a package module without a full project context. For Go, `go run ./path/to/main.go` for a throwaway snippet.
