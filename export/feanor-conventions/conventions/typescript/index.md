---
type: convention
title: TypeScript Conventions Index
description: Entry point for TypeScript/JavaScript language rules — type system, module system, code style, and tooling; Next.js framework extensions live in conventions/nextjs/.
applies_to: [typescript]
tags: [typescript]
---

# TypeScript Conventions Index

Four files cover all TypeScript/JavaScript language rules. Load the specific file for the rules you need.

| File | What it covers |
|---|---|
| `type-system.md` | strict mode, type vs interface, unknown/any policy, no-enum, generics, Zod at boundaries |
| `module-system.md` | ESM-only, named exports, no default exports, barrel file rules, path alias setup |
| `code-style.md` | casing per identifier kind, boolean prefixes, no-abbreviation policy, ternary limit, destructuring |
| `tooling.md` | verbatim tsconfig.json and biome.json baselines, CI and pre-commit commands |

`conventions/nextjs/` extends these rules with React/Next.js-specific additions — it does not replace them. When working on a Next.js project, load both.
