---
type: convention
title: Performance
description: Next.js performance rules covering next/font loading, code splitting, bundle discipline, dynamic imports, and next/image optimization.
applies_to: [nextjs]
tags: [nextjs, performance]
---

# Performance

Fast is a requirement, not an afterthought optimized in later — most of it is free if the defaults below are followed from the start; expensive to retrofit if not.

## Fonts

- `next/font/google` (or `next/font/local`) — never a render-blocking `<link>` to an external font CDN. Self-hosted, no extra DNS/connection round-trip, `display: "swap"` so text isn't invisible while the font loads.
- Load only the weights/subsets actually used — not the full family "just in case."

## Rendering & Code Splitting

- Server Components by default (see `components-data.md`) — the App Router's biggest performance lever is *not* shipping component code to the client that didn't need to run there.
- `next/dynamic` for genuinely heavy Client Components not needed on initial paint (a chart library, a rich text editor) — defer their bundle cost until actually rendered.
- Route-level code splitting is automatic in the App Router — don't fight it by importing across route boundaries in ways that defeat it.

## Bundle Discipline

- Minimal dependencies — every added package is bundle weight on someone's connection. Check what a library costs (bundlephobia or equivalent) before adding it for a small need a few lines of code could cover.
- No unused `create-next-app` scaffolding left in (default demo content, unused placeholder assets) — dead weight, however small.
- No kitchen-sink UI kit pulled in for one component — `shadcn/ui`'s copy-in-only-what-you-use model exists specifically to avoid this.

## Images

- `next/image` for anything raster — automatic sizing, lazy loading below the fold, modern format negotiation. A raw `<img>` tag is a regression, not a shortcut.
- Explicit `width`/`height` (or `fill` with a sized container) to avoid layout shift.

## Data Fetching

- Per `components-data.md`: fetch in Server Components with the framework's caching (`revalidate`/`tags`), not client-side waterfalls. A client component fetching after mount is slower by definition than data resolved server-side before the page ships.

## Measure, Don't Guess

- Core Web Vitals (LCP, CLS, INP) are the actual target, not a subjective "feels fast." `@vercel/speed-insights` or equivalent for a deployed project — a number to check against, not a vibe.
