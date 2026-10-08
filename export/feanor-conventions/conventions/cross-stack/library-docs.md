---
type: convention
title: Library and Framework Documentation
description: Rules for checking current documentation before implementing against a pinned framework version, so generated code matches the version actually installed rather than the model's training data.
applies_to: [all]
tags: [docs, dependencies, frameworks]
---

# Library and Framework Documentation

A model's knowledge of a framework is fixed at training time; the project's version is fixed in [`../versions.toml`](../versions.toml). These are rarely the same, and the gap is invisible — code written against the wrong version compiles, reads correctly, and fails at runtime or in review.

## The Rule

**Before implementing against a framework or library at a pinned version, check the documentation for that version.**

- Prefer a documentation lookup tool (Context7 MCP or equivalent) when one is available — it returns version-scoped docs directly.
- Otherwise use the official docs for the installed version, not a search result that may describe a different major.
- The installed version is authoritative: read it from `package.json` / `pyproject.toml` / `go.mod`, not from memory or from what seems current.

## When This Matters Most

- **A major version boundary.** APIs are renamed and removed across majors. Next.js App Router, React Server Components, SQLAlchemy 1.x vs 2.x, and Pydantic v1 vs v2 all changed enough that confidently-written code from the wrong major is wrong throughout.
- **Anything that "should obviously work" but does not.** That is the signature of a version mismatch, not a typo — check the docs before debugging further.
- **A config or CLI flag.** These change more freely than APIs and are rarely deprecated loudly. A flag that silently does nothing is worse than one that errors.

## Record What You Checked

When a ticket's implementation depended on version-specific behaviour, note the version consulted in the ticket. A reviewer cannot otherwise tell a deliberate version-specific choice from a guess that happened to work.

## Why This Is Not a Gate

Whether documentation was genuinely consulted cannot be checked mechanically, so this stays a rule you follow rather than a script that blocks. The mechanical half is real and already enforced: the scaffold scripts install pinned versions and `scripts/audit-mechanical.py` reports drift from [`../versions.toml`](../versions.toml). That catches the wrong version being *installed*; only this rule catches the wrong version being *coded against*.
