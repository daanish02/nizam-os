---
type: convention
title: TypeScript Tooling Config
description: Verbatim tsconfig.json strict baseline and biome.json baseline (lint + format, replaces ESLint + Prettier), plus CI and pre-commit commands.
applies_to: [typescript]
tags: [typescript, tooling, biome, tsconfig]
---

# TypeScript Tooling Config

## tsconfig.json Baseline

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "moduleResolution": "bundler",
    "strict": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "isolatedModules": true,
    "skipLibCheck": true,
    "paths": { "@/*": ["./src/*"] }
  }
}
```

## biome.json Baseline

Biome replaces ESLint and Prettier — do not add both.

```json
{
  "$schema": "https://biomejs.dev/schemas/1.9.4/schema.json",
  "organizeImports": { "enabled": true },
  "linter": {
    "enabled": true,
    "rules": { "recommended": true }
  },
  "formatter": {
    "enabled": true,
    "indentStyle": "space",
    "indentWidth": 2,
    "lineWidth": 100
  }
}
```

## CI

- `tsc --noEmit` must pass before merge — type errors block the build.

## Pre-commit

- `bunx biome check --write` runs on staged files.
- Hook configuration: see `../git/pre-commit-hooks.md`.
