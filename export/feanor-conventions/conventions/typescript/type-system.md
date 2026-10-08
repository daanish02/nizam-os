---
type: convention
title: TypeScript Type System Rules
description: Strict mode settings, type vs interface choice, unknown/any policy, no-enum rule, generics naming, utility types, Zod at boundaries — applies to all TypeScript projects.
applies_to: [typescript]
tags: [typescript, types]
---

# TypeScript Type System Rules

## Strict Mode

- `strict: true` in `tsconfig.json`, no exceptions.
- Additional flags required alongside strict:

```json
{
  "compilerOptions": {
    "noImplicitAny": true,
    "strictNullChecks": true,
    "noUncheckedIndexedAccess": true,
    "exactOptionalPropertyTypes": true
  }
}
```

## type vs interface

- `type` for object shapes, unions, and intersections.
- `interface` only when declaration merging is required (e.g., extending third-party types like `Express.Request`).

## unknown and any

- `unknown` over `any` for external or untyped data — forces an explicit narrowing step.
- `any` is allowed only with an inline comment: `// any: <reason>`.

## No enum

- No TypeScript `enum`. Use `as const` object + derived type:

```ts
const Status = { Active: 'active', Inactive: 'inactive' } as const;
type Status = typeof Status[keyof typeof Status];
```

- Reason: `enum` compiles to runtime objects with surprising behavior; `as const` is zero-cost and fully type-safe.

## Generics

- Single type parameter: `T`.
- Multiple parameters: descriptive names — `TKey`, `TValue`, `TInput`, `TOutput`.
- Always constrain with `extends` when the shape is known: `<T extends Record<string, unknown>>`.

## Utility Types

- Use built-ins over manual re-declaration: `Partial<>`, `Pick<>`, `Omit<>`, `Readonly<>`, `Required<>`.
- `as const` for literal type inference on config objects and lookup tables.

## Zod at Boundaries

- Use Zod for runtime validation at system boundaries: API input, environment variables, external service responses.
- Internal domain logic trusts TypeScript types — no runtime validation inside business logic.
