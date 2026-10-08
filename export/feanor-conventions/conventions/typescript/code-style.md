---
type: convention
title: TypeScript Code Style & Naming
description: Casing rules per identifier kind, boolean prefixes, no-abbreviation policy, ternary limit, destructuring — applies to all TypeScript/JavaScript code.
applies_to: [typescript]
tags: [typescript, style, naming]
---

# TypeScript Code Style & Naming

## Casing

| Identifier kind | Convention |
|---|---|
| Types, interfaces, classes, React components, generic params | PascalCase |
| Variables, functions, methods, custom hooks | camelCase |
| Non-component filenames, directories | kebab-case |
| Environment variable names | SCREAMING_SNAKE_CASE |

## Custom Hooks

- Must have `use` prefix: `useOrderStatus`, `useAuthUser`.

## Boolean Variables

- `is`/`has`/`can` prefix mandatory — reads as a question and distinguishes from other types.
- Examples: `isLoading`, `hasPermission`, `canSubmit`.

## Abbreviations

- No abbreviations except this approved list: `id`, `url`, `api`, `db`, `dto`, `ctx`, `fn`, `ts`, `js`.
- Spell everything else out: `config` not `cfg`, `error` not `err`, `response` not `res`.

## Ternary

- Max one level. Nested ternary must become a named variable or early return.

```ts
// bad
const label = isActive ? (isPrimary ? 'Primary' : 'Secondary') : 'Inactive';

// good
if (!isActive) return 'Inactive';
const label = isPrimary ? 'Primary' : 'Secondary';
```

## Destructuring & Spread

- Destructure objects at the function signature, not inside the body.
- Spread (`...`) for shallow copying. Never use spread to mutate an existing object.

## Magic Values

- No magic numbers or strings inline. Name them as constants at the top of the file.
