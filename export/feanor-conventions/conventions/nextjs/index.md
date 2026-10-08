---
type: convention
title: Next.js Conventions Index
description: Next.js-specific layout, components/data, styling, and performance standards for frontends; cross-stack topics live in ../cross-stack/ and TypeScript language rules live in ../typescript/.
applies_to: [nextjs]
tags: [nextjs]
---

# Next.js Conventions

Next.js is used for **frontend only**. Package manager: **Bun**.

Cross-stack topics (auth, caching, error-handling, module-boundaries, observability-logging, rate-limiting, security, testing, dependency-management) moved to [`../cross-stack/`](../cross-stack/). TypeScript language-level rules (type system, module system, code style) moved to [`../typescript/`](../typescript/). The files below are Next.js/React-specific only.

## Next.js-Specific Files

- [accessibility.md](./accessibility.md) - WCAG 2.1 AA baseline: semantic structure, keyboard/focus, forms, ARIA, motion, and the Biome a11y lint gate.
- [code-style-naming.md](./code-style-naming.md) - React/Next.js naming and code-style patterns (TypeScript language rules live in `../typescript/`).
- [components-data.md](./components-data.md) - Server vs. Client Components, data fetching, forms/validation, state minimalism.
- [performance.md](./performance.md) - Fonts, code splitting, bundle discipline, images, Core Web Vitals.
- [project-layout.md](./project-layout.md) - App Router structure, domain-based feature folders.
- [styling-ui.md](./styling-ui.md) - Tailwind + shadcn/ui, deliberate design identity, no-flash light/dark mode.

## Cross-Stack (all languages)

See [`../cross-stack/`](../cross-stack/) for: auth, caching, error-handling, module-boundaries, observability-logging, rate-limiting, security, testing, dependency-management.

## TypeScript Language Rules

See [`../typescript/`](../typescript/) for: type-system, module-system, code-style, tooling.

## Explicitly not used by default

No heavy global-state library (Redux, MobX) as a default — Server Components + Server Actions + URL state cover most needs; add one only when a project genuinely needs client-side state that outlives a page (documented decision, not a starting default).
