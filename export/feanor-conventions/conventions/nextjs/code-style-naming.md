---
type: convention
title: Next.js Code Style & Naming
description: React component file naming, Next.js default-export exceptions, composition patterns, and control flow — Next.js/React-specific rules that extend the TypeScript conventions.
applies_to: [typescript]
tags: [nextjs, style, naming]
---

# Next.js Code Style & Naming

For TypeScript language rules (strict mode, type system, naming) see `../typescript/`.

## Component Files

- One component per file. Filename matches the exported component name: `OrderCard.tsx` exports `OrderCard`.
- Component files use PascalCase. Non-component files (utils, schemas, actions) use kebab-case.

## Default Exports

- No default exports except for Next.js special files that require them: `page.tsx`, `layout.tsx`, `error.tsx`, `not-found.tsx`.
- Named exports everywhere else — consistent auto-import behavior, easier refactors.

## Composition

- Prefer composition (children, render props, slots) over deeply-nested conditional JSX.
- A component doing three unrelated things should split into smaller components.

## Control Flow

- Early return over nested conditionals — keeps the happy path at the left margin.
- Destructure props at the function signature, not inside the body.

## Comments & Discipline

- Code self-documenting first: good names, small components.
- Comments only where logic is genuinely non-obvious. No walls of text.
- DRY, YAGNI, KISS, SRP apply — don't build a prop for a case that doesn't exist yet.
