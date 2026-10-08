---
type: convention
title: Project Layout
description: Next.js project directory structure covering App Router layout, domain-based features/ organisation, shared components, and lib/ boundaries.
applies_to: [nextjs]
tags: [nextjs, layout, architecture]
---

# Project Layout

## Structure

```text
frontend/
├── src/
│   ├── app/                      # App Router — routes only, thin
│   │   ├── (marketing)/
│   │   ├── orders/
│   │   │   ├── page.tsx
│   │   │   ├── layout.tsx
│   │   │   ├── error.tsx
│   │   │   └── loading.tsx
│   │   └── api/                  # only if a real API route is needed
│   ├── features/                 # domain-based, same philosophy as backend project-layout.md
│   │   ├── orders/
│   │   │   ├── components/
│   │   │   ├── actions.ts        # Server Actions for this domain
│   │   │   ├── queries.ts
│   │   │   └── schema.ts         # Zod schemas
│   │   └── billing/
│   ├── components/ui/            # shadcn/ui primitives + genuinely shared components ONLY
│   ├── lib/                      # genuinely cross-domain utilities only, not a catch-all
│   ├── app/robots.ts             # public-facing apps only — see "Robots & Sitemap" below
│   └── app/sitemap.ts            # public-facing apps only
├── public/
├── package.json              # "next": "~15.3.0", "typescript": "~5.8.0"
└── bun.lock                  # older Bun versions write bun.lockb instead
```

- `app/` holds routing structure only (`page.tsx`, `layout.tsx`, `error.tsx`, `loading.tsx`, `not-found.tsx`) — actual feature logic (components, data access, validation) lives in `features/<domain>/`, mirroring the backend's domain-based-package philosophy.
- `components/ui/` is for shared design-system primitives (shadcn/ui-generated components) and components genuinely used across 2+ domains — not a dumping ground for anything reusable-in-theory.
- `lib/` is for genuinely cross-domain code (a fetch wrapper, a date helper) — same "not a catch-all" rule as backend `utils/`.
- Route groups (`(marketing)`) used to organize routes without affecting the URL, when a section of the app has a distinct layout.
- **Tunables split into two tiers, same as the backend conventions:** cross-cutting config (used by 2+ features, or env-derived — only `NEXT_PUBLIC_`-prefixed values reach the client, see `security.md`) lives in one `lib/config.ts`. A constant only one file uses is declared `UPPER_SNAKE_CASE` at the top of that file, not promoted to `lib/config.ts` — promote only once a second file genuinely needs it.

## Robots & Sitemap

**Conditional — mandatory when the app is publicly reachable and meant to be indexed** (marketing site, public docs, a storefront). Skip it for an internal tool or an app that is entirely behind auth — see `docs/CAPABILITIES.md`'s conditional tier.

Generate both as typed route handlers, not static files in `public/` — App Router resolves `app/robots.ts` and `app/sitemap.ts` automatically, and typed output catches a malformed entry at build time instead of silently shipping a broken one:

```typescript
// app/robots.ts
import type { MetadataRoute } from "next";

export default function robots(): MetadataRoute.Robots {
  return {
    rules: { userAgent: "*", allow: "/", disallow: ["/api/"] },
    sitemap: "https://example.com/sitemap.xml",
  };
}
```

- **`robots.txt` is a crawler directive, not access control.** It is a public, unauthenticated file — anything listed in `disallow` is thereby advertised to everyone reading it, hostile crawlers included. Never list an admin path, an internal tool, or anything sensitive there. Keeping a route out of the crawl and keeping it out of unauthorized hands are different problems — the second is `access-control.md`'s job, not this file's.
- Real exclusion of a page from search results is `X-Robots-Tag: noindex` on that response — see `security.md`. `robots.txt` only asks well-behaved crawlers not to *visit*; `noindex` asks them not to *index* what they already fetched, and is the one that actually keeps a page out of search results.
- `app/sitemap.ts` lists only genuinely public, indexable routes. Do not enumerate dynamic user-owned pages (`/orders/{id}`) into a public sitemap.

## Toolchain Version Pins

Pin these in `package.json` to prevent version drift. **The authoritative numbers live in [`../versions.toml`](../versions.toml)** — the scaffold scripts and `audit-mechanical.py` read them from there. The table below is the rationale; if it disagrees with `versions.toml`, `versions.toml` wins.

| Package      | Pin              | Rationale                                                                    |
| :----------- | :--------------- | :--------------------------------------------------------------------------- |
| `next`       | `~15.3.0`        | Patch-flexible, minor-locked. Next.js minor releases can break App Router behavior. |
| `typescript` | `~5.8.0`         | Patch-flexible, minor-locked. Minor TS releases occasionally tighten type-checking in breaking ways. |

**Bun runtime:** pin in `.bun-version` at project root: `1.3.x` (or `>=1.3.0,<1.4.0` in tooling docs). Bun minor releases can change module resolution and lockfile format. Write `1.3` (omit patch) in `.bun-version` — Bun resolves to latest patch automatically.

## Server vs. Client

- Default to Server Components. A component becomes a Client Component (`"use client"`) only when it needs interactivity, browser APIs, or React state/effects — not by default, not "just in case."
- Push `"use client"` as far down the tree as possible — a whole page doesn't need to be client-rendered because one button needs an `onClick`.
