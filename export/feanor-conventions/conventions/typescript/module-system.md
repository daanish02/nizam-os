---
type: convention
title: TypeScript Module System Rules
description: ESM-only, named exports, no default exports (except framework exceptions), barrel file rules, and path alias setup — applies to all TypeScript projects.
applies_to: [typescript]
tags: [typescript, modules, imports]
---

# TypeScript Module System Rules

## ESM Only

- No CommonJS `require()`. Use `import`/`export` everywhere.
- `"module": "ESNext"` and `"moduleResolution": "bundler"` in tsconfig (see `tooling.md`).

## Exports

- Named exports always.
- No default exports except where the framework mandates it — in Next.js: `page.tsx`, `layout.tsx`, `error.tsx`, `not-found.tsx`.
- Reason: named exports make auto-import deterministic and refactors safe.

## Import Order

1. External packages (`react`, `zod`, `@tanstack/react-query`, …)
2. Internal `@/` aliases (`@/lib/…`, `@/components/…`)
3. Relative paths (`./utils`, `../schema`)

Biome's `organizeImports` enforces this automatically.

## Barrel Files

- `index.ts` barrels only at shared layer boundaries: `lib/`, `components/ui/`, `types/`, `hooks/`.
- Never create a barrel per component or per feature folder — they slow down bundlers and create circular dependency risks.

## Path Aliases

- `@/` maps to `src/`. Defined in `tsconfig.json` paths, mirrored in `biome.json`.

```json
"paths": { "@/*": ["./src/*"] }
```

- No other aliases. Relative imports for intra-feature references.
