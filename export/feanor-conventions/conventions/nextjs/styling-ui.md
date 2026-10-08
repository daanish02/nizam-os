---
type: convention
title: Styling & UI
description: Next.js styling rules covering Tailwind CSS utility classes, shadcn/ui component primitives, design token definition, and light/dark mode. Accessibility rules live in accessibility.md.
applies_to: [nextjs]
tags: [nextjs, styling, ui, design-system]
---

# Styling & UI

## Stack

- Tailwind CSS for styling — utility classes in JSX, no separate CSS-in-JS runtime, no hand-written CSS modules unless Tailwind genuinely can't express something.
- `shadcn/ui` for component primitives (built on Radix) — copied into `components/ui/` and owned by the project, not a black-box npm dependency. Customize freely; that's the point of the pattern.
- Design tokens (colors, spacing, radii) defined once in `tailwind.config.ts` as CSS custom properties, referenced everywhere — no magic hex values or pixel values scattered through components.

## Design Identity — Deliberate, Not Generic

**No default AI-generated look.** The reflexive purple/indigo gradient, default `Inter` everywhere, default shadcn slate palette, and default rounded-lg-on-everything read as generic precisely because they're everyone's unexamined default. Every project makes an actual, stated choice instead:

- **Accent color:** picked for this specific project (its brand, its domain, its mood) — not defaulted to indigo/violet because that's shadcn's out-of-the-box demo color. State the choice and why, even briefly.
- **Typography:** decided on purpose. A generic SaaS product might genuinely want a clean sans-serif — that's fine _if it was actually decided_, not just left as whatever `create-next-app` scaffolded. A data-heavy/technical tool might warrant a monospace-leaning identity instead. The rule is "chosen," not "must be unusual."
- **Shape language:** border-radius, shadow depth, spacing rhythm — pick a consistent point of view and apply it everywhere, rather than leaving every component at whatever shadcn's defaults happen to be.

This doesn't mean reinventing the wheel per project — Tailwind + shadcn/ui stays the stack. It means the tokens in `tailwind.config.ts` get actually set, not left at scaffold defaults.

## Light & Dark Mode — Mandatory, No Flash

Every project ships both. The failure mode to avoid is a flash of the wrong theme on load (light theme flashing before a dark preference applies, or vice versa) — this is a correctness requirement, not a nice-to-have:

- Theme driven by a `data-theme` attribute (or class) on `<html>`, matching Tailwind's `dark:` variant configured for class/attribute-based (not `prefers-color-scheme`-only) toggling — so an explicit user choice can override the OS preference.
- A small **synchronous, pre-hydration inline script** in the root layout reads the persisted preference (`localStorage`) and sets the attribute **before first paint** — this is what actually prevents the flash; a `useEffect`-based toggle runs too late.
- Preference persisted to `localStorage`, respected on next visit.
- Both themes get real design attention (contrast, accent-color legibility) — dark mode isn't "light mode with inverted CSS variables and hope."

## Accessibility

WCAG 2.1 AA baseline (semantic structure, keyboard/focus, forms, ARIA, contrast, lint gate) — see `accessibility.md`. Color tokens defined here must still meet AA contrast in both themes.

## Responsiveness

**Mobile-first vs. desktop-first is a decision made during `/prd`, per `meta/requirements-checklist.md`'s funnel — never assumed here.** Once decided:

- **Mobile-first:** Tailwind's default breakpoint direction (`sm:`, `md:`, `lg:` as progressive enhancement) — base styles target mobile, larger breakpoints add complexity.
- **Desktop-first:** base styles target the primary desktop layout, with `max-w-*`/container queries or a narrow single breakpoint override (e.g. one `max-md:` treatment collapsing a multi-panel layout to stacked) for small screens — appropriate for a dense, desktop-primary tool where the mobile view is a simplified fallback, not the primary experience.
- Either way: **must not break** at any real viewport width in between — test the actual breakpoints chosen, not just the two extremes.
